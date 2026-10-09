import Foundation
import IOKit.ps

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
    public static let version = "1.5.3"
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
        var samples: [(time: Date, cpu: UInt64, gpu: UInt64)] = []
        var gpuProblem: String?
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
        let threads = config.cpuThreads
        updateStatus { $0.server = source.serverDescription; $0.threads = threads }
        var lock: MiningLock?
        guard waitForMiningLock(&lock) else { return }
        defer { withExtendedLifetime(lock) {} }  // held until the gateway and engine have stopped
        guard startHashing(threads: threads) else {
            Engine.stop()  // whatever started before mining was stopped
            return
        }

        while !shouldStop {
            let now = Date()
            if !pausedForBattery(now) { work(source, now) }
            reportGPUProblem()
            publishStats(now)
            Thread.sleep(forTimeInterval: Self.tickInterval)
        }
        source.stop()
        Engine.stop()
        log("Stopped")
    }

    /// Starts the CPU threads and/or the GPU; false if nothing could start (the
    /// reason is shown) or mining was stopped meanwhile.
    private func startHashing(threads: Int) -> Bool {
        if threads > 0 { guard startCPU(threads: threads) else { return false } }
        if config.useGPU { guard startGPU() else { return false } }
        if Engine.isRunning { return true }
        let reason = config.useGPU || threads > 0
            ? "Neither CPU nor GPU mining could start (see the log). Check Performance settings."
            : "CPU and GPU mining are both off; turn one on in Performance settings."
        log("Problem: " + reason)
        setWaiting(reason)
        while !shouldStop { Thread.sleep(forTimeInterval: Self.tickInterval) }
        return false
    }

    /// Starts the CPU threads, or logs why not; false only if stopped meanwhile.
    private func startCPU(threads: Int) -> Bool {
        do {
            guard try whenEngineFree({ try Engine.start(threads: threads, lowPriority: config.lowPriority) }) != nil else { return false }
            log("Started \(threads) CPU hashing thread\(threads == 1 ? "" : "s") (\(config.mode.displayName); \(Engine.kernel) kernel)")
            if CPUInfo.isTranslated { log("Warning: " + CPUInfo.rosettaWarning) }
        } catch {
            log("Problem: CPU mining could not start: \(error.localizedDescription)")
        }
        return true
    }

    /// Starts GPU mining, or logs why not; false only if stopped meanwhile.
    private func startGPU() -> Bool {
        do {
            let load = config.gpuLoad, responsive = config.lowPriority
            guard let name = try whenEngineFree({ try Engine.startGPU(load: load, responsive: responsive) }) else { return false }
            updateStatus { $0.gpuName = name }
            log("Started GPU mining on the \(name) at \(load)% load\(responsive ? ", in short bursts to keep the Mac responsive" : "")")
        } catch {
            log("Problem: GPU mining is unavailable: \(error.localizedDescription)")
        }
        return true
    }

    /// Runs `start`, waiting while the self-test has the engine; nil if mining was
    /// stopped meanwhile.
    private func whenEngineFree<T>(_ start: () throws -> T) throws -> T? {
        while true {
            do {
                return try start()
            } catch is Engine.Busy {
                guard !shouldStop else { return nil }
                setWaiting("Waiting for the self-test to finish")
                Thread.sleep(forTimeInterval: 1)
            }
        }
    }

    /// Logs GPU problems once, and when the GPU recovers.
    private func reportGPUProblem() {
        let problem = Engine.gpuProblem
        guard problem != loop.gpuProblem else { return }
        log(problem.map { "Problem: GPU: \($0) (will retry)" } ?? "GPU mining recovered")
        loop.gpuProblem = problem
    }

    /// Waits while another miner on this Mac is mining (see MiningLock); false if
    /// stopped meanwhile. A lock file that can't be created doesn't block mining.
    private func waitForMiningLock(_ lock: inout MiningLock?) -> Bool {
        var reported = false
        while !shouldStop {
            switch MiningLock.acquire() {
            case .acquired(let acquired):
                lock = acquired
                if reported { log("The other miner stopped; starting") }
                return true
            case .unavailable:
                return true
            case .heldBy(let path):
                let message = "\(MiningLock.describe(path).capitalizedFirst) is already mining on this Mac. Quit it to mine here."
                if !reported { log("Waiting: " + message) }
                reported = true
                setWaiting(message)
                for _ in 0..<25 where !shouldStop { Thread.sleep(forTimeInterval: Self.tickInterval) }
            }
        }
        return false
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
        let cpu = Engine.cpuHashes, gpu = Engine.gpuHashes
        let hashes = cpu &+ gpu
        loop.samples.append((now, cpu, gpu))
        loop.samples.removeAll { now.timeIntervalSince($0.time) > Self.hashrateWindow }
        guard let first = loop.samples.first else { return }
        let paused = loop.paused
        updateStatus { s in
            s.totalHashes = hashes
            let window = now.timeIntervalSince(first.time)
            if window > 0.5 {
                s.cpuHashrate = paused ? 0 : Double(cpu &- first.cpu) / window
                s.gpuHashrate = paused ? 0 : Double(gpu &- first.gpu) / window
                s.hashrate = s.cpuHashrate + s.gpuHashrate
            }
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
