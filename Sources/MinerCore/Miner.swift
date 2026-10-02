import Foundation
import IOKit.ps

public struct MinerConfig: Codable, Equatable {
    public var mode: MiningMode = .datum
    public var node = NodeConfig()
    public var payoutAddress = ""
    public var coinbaseTag = "/BLAKE2b Miner/"
    public var gateway = GatewaySettings()
    public var stratum = StratumConfig()
    public var threads = CPUInfo.cores
    /// Run hashing threads at utility priority so the Mac stays responsive.
    public var lowPriority = false
    public var pauseOnBattery = true
    public var preventSleep = false

    public init() {}

    /// Tolerates settings saved by older versions: missing keys keep their defaults.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func get<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T { (try? c.decodeIfPresent(T.self, forKey: key)) ?? fallback }
        let d = MinerConfig()
        mode = get(.mode, d.mode)
        node = get(.node, d.node)
        payoutAddress = get(.payoutAddress, d.payoutAddress)
        coinbaseTag = get(.coinbaseTag, d.coinbaseTag)
        gateway = get(.gateway, d.gateway)
        stratum = get(.stratum, d.stratum)
        threads = get(.threads, d.threads)
        lowPriority = get(.lowPriority, d.lowPriority)
        pauseOnBattery = get(.pauseOnBattery, d.pauseOnBattery)
        preventSleep = get(.preventSleep, d.preventSleep)
    }
}

protocol WorkSource: AnyObject {
    var miner: Miner? { get set }
    var serverDescription: String { get }
    func start() throws
    func tick() throws
    func submit(jobID: UInt64, nonce8: Data)
    func stop()
}

/// Runs one mining session: a work source feeding the native engine.
public final class Miner: @unchecked Sendable {
    public static let version = "1.1.0"

    public weak var delegate: MinerDelegate?
    public private(set) var config = MinerConfig()

    private let lock = NSLock()
    private var status = MinerStatus()
    private var thread: Thread?
    private var stopRequested = false
    private let finished = DispatchSemaphore(value: 0)
    private var activity: NSObjectProtocol?

    public init() {}

    public var isRunning: Bool { lock.lock(); defer { lock.unlock() }; return thread != nil }

    public var currentStatus: MinerStatus { lock.lock(); defer { lock.unlock() }; return status }

    public func start(_ config: MinerConfig) {
        lock.lock()
        guard thread == nil else { lock.unlock(); return }
        self.config = config
        stopRequested = false
        status = MinerStatus()
        status.state = .starting
        status.mode = config.mode
        status.startedAt = Date()
        let t = Thread { [weak self] in self?.run() }
        t.name = "miner-control"
        t.qualityOfService = .userInitiated
        thread = t
        lock.unlock()
        let options: ProcessInfo.ActivityOptions = config.preventSleep ? [.userInitiated, .idleSystemSleepDisabled] : .userInitiatedAllowingIdleSystemSleep
        activity = ProcessInfo.processInfo.beginActivity(options: options, reason: "Mining")
        t.start()
    }

    /// Stops mining and waits for the engine threads to exit.
    public func stop() {
        lock.lock()
        guard thread != nil else { lock.unlock(); return }
        stopRequested = true
        lock.unlock()
        finished.wait()
        lock.lock()
        thread = nil
        status.state = .stopped
        status.hashrate = 0
        let s = status
        lock.unlock()
        if let a = activity { ProcessInfo.processInfo.endActivity(a) }
        activity = nil
        delegate?.miner(status: s)
    }

    // MARK: Called by work sources (control thread)

    func log(_ line: String) { delegate?.miner(log: line) }

    func updateStatus(_ change: (inout MinerStatus) -> Void) {
        lock.lock(); change(&status); lock.unlock()
    }

    func setMining() { updateStatus { $0.state = .mining; $0.lastError = nil } }

    func setWaiting(_ reason: String) { updateStatus { $0.state = .waiting(reason) } }

    func recordBlock(_ block: FoundBlock) {
        if block.result == "accepted" { updateStatus { $0.blocksFound += 1 } }
        delegate?.miner(found: block)
    }

    // MARK: Control loop

    private var shouldStop: Bool { lock.lock(); defer { lock.unlock() }; return stopRequested }

    private func run() {
        var gateway: DatumGatewayProcess?
        let source: WorkSource
        switch config.mode {
        case .solo:
            source = SoloSource(node: config.node, address: config.payoutAddress, coinbaseTag: config.coinbaseTag)
        case .stratum:
            source = StratumSource(config: config.stratum)
        case .datum:
            let g = DatumGatewayProcess(settings: config.gateway, node: config.node, payoutAddress: config.payoutAddress) { [weak self] in
                self?.log($0)
            }
            gateway = g
            var local = StratumConfig()
            local.url = g.stratumURL
            local.user = config.payoutAddress
            source = StratumSource(config: local)
        }
        source.miner = self
        updateStatus { $0.server = source.serverDescription; $0.threads = self.config.threads }

        let threads = max(1, min(config.threads, 256))
        do {
            try Engine.start(threads: threads, lowPriority: config.lowPriority)
        } catch {
            updateStatus { $0.lastError = error.localizedDescription; $0.state = .waiting(error.localizedDescription) }
            log(error.localizedDescription)
            finished.signal()
            return
        }
        let modeName = ["datum": "your own DATUM Gateway", "solo": "solo mining via node", "stratum": "Stratum server"][config.mode.rawValue]!
        log("Started \(threads) hashing threads (\(modeName))")
        var gatewayRestartAt = Date.distantPast
        var gatewayStarted = false

        var started = false
        var retryAt = Date.distantPast
        var lastError: String?
        var paused = false
        var samples: [(Date, UInt64)] = []
        var lastPublish = Date.distantPast
        var lastBatteryCheck = Date.distantPast
        var onBattery = false

        while !shouldStop {
            let now = Date()
            if config.pauseOnBattery && now.timeIntervalSince(lastBatteryCheck) >= 5 {
                lastBatteryCheck = now
                onBattery = Self.onBatteryPower()
            }
            if config.pauseOnBattery && onBattery {
                if !paused { Engine.clearWork(); log("Paused: running on battery power") }
                paused = true
                setWaiting("Paused while on battery power")
            } else {
                if paused { log("Resumed: back on power adapter") }
                paused = false
                if let g = gateway, !g.isRunning, now >= gatewayRestartAt {
                    if gatewayStarted {
                        log("DATUM Gateway stopped unexpectedly (\(g.recentOutput)); restarting")
                        Engine.clearWork()
                    }
                    do {
                        if config.payoutAddress.trimmingCharacters(in: .whitespaces).isEmpty {
                            throw MinerError.config("Set a payout address first.")
                        }
                        if let pool = DatumPool.find(config.gateway.poolID) {
                            // Never send test-chain work to a real pool.
                            let info = try NodeRPC(config.node, timeout: 10).call("getblockchaininfo") as? [String: Any]
                            let chain = info?["chain"] as? String ?? "?"
                            guard chain == "main" else {
                                throw MinerError.config("\(pool.name) is a mainnet pool, but your node is on \(chain). Choose \"None: solo\" or connect a mainnet node.")
                            }
                        }
                        try g.start()
                        gatewayStarted = true
                        retryAt = now.addingTimeInterval(3)  // let it fetch a template and open its Stratum port
                    } catch {
                        let message = error.localizedDescription
                        if message != lastError { log("Problem: \(message) (will retry)") }
                        lastError = message
                        updateStatus { $0.state = .waiting(message); $0.lastError = message }
                    }
                    gatewayRestartAt = now.addingTimeInterval(10)
                }
                if let g = gateway {
                    let text: String
                    switch g.poolState {
                    case .none: text = "Solo through your gateway · your node builds the blocks"
                    case .connecting: text = "Connecting to \(DatumPool.find(config.gateway.poolID)?.name ?? "pool")… · your node builds the blocks"
                    case .connected(let name): text = "Pooled with \(name) · your node builds the blocks"
                    case .problem(let p): text = "Pool problem: \(p)"
                    }
                    updateStatus { $0.gatewayStatus = text }
                }
                if now >= retryAt && (gateway == nil || gateway!.isRunning) {
                    do {
                        if !started {
                            try source.start()
                            started = true
                        }
                        try source.tick()
                        if lastError != nil { log("Recovered") }
                        lastError = nil
                    } catch {
                        let message = error.localizedDescription
                        if message != lastError { log("Problem: \(message) (will retry)") }
                        lastError = message
                        Engine.clearWork()
                        updateStatus { $0.state = .waiting(message); $0.lastError = message }
                        retryAt = now.addingTimeInterval(5)
                    }
                }
                while let (job, nonce) = Engine.takeSolution() {
                    source.submit(jobID: job, nonce8: nonce)
                }
            }

            if now.timeIntervalSince(lastPublish) >= 1 {
                lastPublish = now
                let h = Engine.hashes
                samples.append((now, h))
                samples.removeAll { now.timeIntervalSince($0.0) > 30 }
                updateStatus { s in
                    s.totalHashes = h
                    if let first = samples.first, now.timeIntervalSince(first.0) > 0.5 {
                        s.hashrate = Double(h - first.1) / now.timeIntervalSince(first.0)
                    }
                    if let start = s.startedAt { s.averageHashrate = Double(h) / max(now.timeIntervalSince(start), 1) }
                    if let d = s.networkDifficulty, s.hashrate > 0, s.mode == .solo {
                        s.expectedSecondsPerBlock = d * 4_294_967_296 / s.hashrate
                    }
                    if paused { s.hashrate = 0 }
                }
                delegate?.miner(status: currentStatus)
            }
            Thread.sleep(forTimeInterval: 0.2)
        }
        source.stop()
        gateway?.stop()
        Engine.stop()
        log("Stopped")
        finished.signal()
    }

    static func onBatteryPower() -> Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String? else { return false }
        return type == kIOPMBatteryPowerKey
    }
}
