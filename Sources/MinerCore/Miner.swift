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

    /// Missing or invalid keys keep their defaults (see `decode(_:or:)`).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = MinerConfig()
        mode = c.decode(.mode, or: d.mode)
        node = c.decode(.node, or: d.node)
        payoutAddress = c.decode(.payoutAddress, or: d.payoutAddress)
        coinbaseTag = c.decode(.coinbaseTag, or: d.coinbaseTag)
        gateway = c.decode(.gateway, or: d.gateway)
        stratum = c.decode(.stratum, or: d.stratum)
        threads = c.decode(.threads, or: d.threads)
        lowPriority = c.decode(.lowPriority, or: d.lowPriority)
        pauseOnBattery = c.decode(.pauseOnBattery, or: d.pauseOnBattery)
        preventSleep = c.decode(.preventSleep, or: d.preventSleep)
    }
}

/// Where work comes from: a node, a Stratum server, or the bundled gateway.
/// All methods are called on the miner's control thread.
protocol WorkSource: AnyObject {
    var miner: Miner? { get set }
    var serverDescription: String { get }
    /// One-time checks before mining; throwing makes the miner retry.
    func start() throws
    /// Called about five times a second: fetch or refresh work.
    func tick() throws
    func submit(jobID: UInt64, nonce8: Data)
    func stop()
}

/// Runs one mining session: a work source feeding the native engine.
public final class Miner: @unchecked Sendable {  // shared state is guarded by `lock`
    public static let version = "1.3.3"
    static let userAgent = "BLAKE2bMiner/\(version)"

    public weak var delegate: MinerDelegate?
    public private(set) var config = MinerConfig()

    private let lock = NSLock()
    private var status = MinerStatus()
    private var thread: Thread?
    private var stopRequested = false
    private let finished = DispatchSemaphore(value: 0)
    private var activity: NSObjectProtocol?

    /// Control-loop state; only touched on the control thread.
    private struct Loop {
        var sourceStarted = false
        var retryAt = Date.distantPast
        var lastError: String?
        var paused = false
        var onBattery = false
        var lastBatteryCheck = Date.distantPast
        var lastPublish = Date.distantPast
        var samples: [(time: Date, hashes: UInt64)] = []
    }
    private var loop = Loop()

    private static let tickInterval: TimeInterval = 0.2
    private static let retryDelay: TimeInterval = 5
    private static let hashrateWindow: TimeInterval = 30

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
        let options: ProcessInfo.ActivityOptions = config.preventSleep
            ? [.userInitiated, .idleSystemSleepDisabled] : .userInitiatedAllowingIdleSystemSleep
        activity = ProcessInfo.processInfo.beginActivity(options: options, reason: "Mining")
        t.start()
    }

    /// Stops mining and waits for the engine threads (and any gateway) to exit.
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

    // MARK: For work sources (control thread)

    func log(_ line: String) { delegate?.miner(log: line) }

    func updateStatus(_ change: (inout MinerStatus) -> Void) {
        lock.lock(); change(&status); lock.unlock()
    }

    func setMining() { updateStatus { $0.state = .mining; $0.lastError = nil } }

    func setWaiting(_ reason: String) { updateStatus { $0.state = .waiting(reason) } }

    func recordBlock(_ block: FoundBlock) {
        if block.countsAsFound { updateStatus { $0.blocksFound += 1 } }
        delegate?.miner(found: block)
    }

    // MARK: Control loop

    private var shouldStop: Bool { lock.lock(); defer { lock.unlock() }; return stopRequested }

    private func makeSource() -> WorkSource {
        switch config.mode {
        case .solo: return SoloSource(node: config.node, address: config.payoutAddress, coinbaseTag: config.coinbaseTag)
        case .stratum: return StratumSource(config: config.stratum)
        case .datum: return GatewaySource(config: config)
        }
    }

    private func run() {
        defer { finished.signal() }
        loop = Loop()
        let source = makeSource()
        source.miner = self
        let threads = max(1, min(config.threads, 256))
        updateStatus { $0.server = source.serverDescription; $0.threads = threads }
        // The engine is shared with the self-test; if a test is running, wait for it.
        while true {
            do {
                try Engine.start(threads: threads, lowPriority: config.lowPriority)
                break
            } catch {
                guard !shouldStop else { return }
                setWaiting("Waiting for the self-test to finish")
                Thread.sleep(forTimeInterval: 1)
            }
        }
        log("Started \(threads) hashing threads (\(config.mode.displayName))")
        if CPUInfo.isTranslated { log("Warning: " + CPUInfo.rosettaWarning) }

        while !shouldStop {
            let now = Date()
            if !pausedForBattery(now) { work(source, now) }
            publishStats(now)
            Thread.sleep(forTimeInterval: Self.tickInterval)
        }
        source.stop()
        Engine.stop()
        log("Stopped")
    }

    /// One step: start the source if needed, let it refresh work, and hand it solutions.
    private func work(_ source: WorkSource, _ now: Date) {
        if now >= loop.retryAt {
            do {
                if !loop.sourceStarted {
                    try source.start()
                    loop.sourceStarted = true
                }
                try source.tick()
                if loop.lastError != nil { log("Recovered") }
                loop.lastError = nil
            } catch {
                Engine.clearWork()
                report(error)
                loop.retryAt = now.addingTimeInterval(Self.retryDelay)
            }
        }
        while let (job, nonce) = Engine.takeSolution() {
            source.submit(jobID: job, nonce8: nonce)
        }
    }

    /// Logs a problem once (until it changes) and shows it as the waiting reason.
    private func report(_ error: Error) {
        let message = error.localizedDescription
        if message != loop.lastError { log("Problem: \(message) (will retry)") }
        loop.lastError = message
        updateStatus { $0.state = .waiting(message); $0.lastError = message }
    }

    /// Pauses (and resumes) mining on battery power when configured to.
    private func pausedForBattery(_ now: Date) -> Bool {
        guard config.pauseOnBattery else { return false }
        if now.timeIntervalSince(loop.lastBatteryCheck) >= 5 {
            loop.lastBatteryCheck = now
            loop.onBattery = Self.onBatteryPower()
        }
        if loop.onBattery != loop.paused {
            loop.paused = loop.onBattery
            if loop.paused { Engine.clearWork() }
            log(loop.paused ? "Paused: running on battery power" : "Resumed: back on power adapter")
        }
        if loop.paused { setWaiting("Paused while on battery power") }
        return loop.paused
    }

    /// Updates hashrates about once a second and notifies the delegate.
    private func publishStats(_ now: Date) {
        guard now.timeIntervalSince(loop.lastPublish) >= 1 else { return }
        loop.lastPublish = now
        let hashes = Engine.hashes
        loop.samples.append((now, hashes))
        loop.samples.removeAll { now.timeIntervalSince($0.time) > Self.hashrateWindow }
        guard let first = loop.samples.first else { return }
        let paused = loop.paused
        updateStatus { s in
            s.totalHashes = hashes
            let window = now.timeIntervalSince(first.time)
            if window > 0.5 { s.hashrate = paused ? 0 : Double(hashes - first.hashes) / window }
            if let start = s.startedAt { s.averageHashrate = Double(hashes) / max(now.timeIntervalSince(start), 1) }
            if let d = s.networkDifficulty, s.hashrate > 0, s.mode == .solo {
                s.expectedSecondsPerBlock = d * hashesPerDifficulty / s.hashrate
            }
        }
        delegate?.miner(status: currentStatus)
    }

    static func onBatteryPower() -> Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String? else { return false }
        return type == kIOPMBatteryPowerKey
    }
}
