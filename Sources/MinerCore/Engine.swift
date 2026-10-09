import CEngine
import Foundation

/// The hashing engines: CPU threads (the C engine) and, optionally, the GPU
/// (`GPUEngine`). Work goes to both; solutions and hash counts come from both.
/// A process-wide singleton.
public enum Engine {
    /// Thrown by `start` and `startGPU` while the self-test has the engine.
    public struct Busy: LocalizedError {
        public var errorDescription: String? { "The self-test is using the hashing engine" }
    }

    private static let lock = NSLock()
    private static var gpuEngine: GPUEngine?
    /// The self-test has the CPU engine to itself (see `withSelfTestEngine`).
    private static var selfTesting = false

    /// Starts CPU hashing threads (idle until work is set).
    public static func start(threads: Int, lowPriority: Bool) throws {
        lock.lock()
        defer { lock.unlock() }
        guard !selfTesting else { throw Busy() }
        guard b2m_start(Int32(threads), lowPriority ? 1 : 0) == 0 else {
            throw MinerError.config("Could not start \(threads) hashing threads")
        }
    }

    /// Starts GPU mining; returns the GPU's name.
    /// - Parameters:
    ///   - load: percent of the GPU's time to use, 10...100.
    ///   - responsive: short GPU bursts so the Mac stays smooth.
    @discardableResult
    public static func startGPU(load: Int, responsive: Bool) throws -> String {
        let gpu = try GPUEngine(load: load, responsive: responsive)
        lock.lock()
        guard !selfTesting else { lock.unlock(); throw Busy() }
        let old = gpuEngine
        gpuEngine = gpu
        lock.unlock()
        old?.stop()
        gpu.start()
        return gpu.deviceName
    }

    /// Runs `body` with CPU hashing threads that nothing else uses: the self-test's
    /// engine check. Returns nil without running `body` while mining uses the engine;
    /// mining that starts meanwhile waits (`Busy`).
    static func withSelfTestEngine<T>(threads: Int, _ body: () throws -> T) throws -> T? {
        lock.lock()
        guard !selfTesting, gpuEngine == nil, b2m_threads() == 0 else { lock.unlock(); return nil }
        selfTesting = true
        let started = b2m_start(Int32(threads), 0) == 0
        lock.unlock()
        defer {
            b2m_stop()
            lock.lock()
            selfTesting = false
            lock.unlock()
        }
        guard started else { throw MinerError.config("Could not start \(threads) hashing threads") }
        return try body()
    }

    /// Stops the CPU threads and the GPU (but not a self-test's CPU threads).
    public static func stop() {
        lock.lock()
        if !selfTesting { b2m_stop() }
        let gpu = gpuEngine
        gpuEngine = nil
        lock.unlock()
        gpu?.stop()
    }

    private static var gpu: GPUEngine? { lock.lock(); defer { lock.unlock() }; return gpuEngine }

    /// - Parameters:
    ///   - input: the 80-byte final-stage input; bytes 32..39 are searched.
    ///   - target: solutions must hash to at most this value.
    public static func setWork(jobID: UInt64, input: Data, target: UInt256) {
        precondition(input.count == 80)
        let t = [UInt8](target.bigEndianData)
        [UInt8](input).withUnsafeBufferPointer { b2m_set_work(jobID, $0.baseAddress, t) }
        gpu?.setWork(jobID: jobID, input: input, target: target)
    }

    public static func clearWork() {
        b2m_clear_work()
        gpu?.clearWork()
    }

    /// Returns (job id, the 8 solved bytes at offset 32 of the input).
    public static func takeSolution() -> (UInt64, Data)? {
        var job: UInt64 = 0
        var nonce = [UInt8](repeating: 0, count: 8)
        if b2m_take_solution(&job, &nonce) == 1 { return (job, Data(nonce)) }
        return gpu?.takeSolution()
    }

    public static var hashes: UInt64 { cpuHashes &+ gpuHashes }
    public static var cpuHashes: UInt64 { b2m_hashes() }
    public static var gpuHashes: UInt64 { gpu?.hashes ?? 0 }

    /// CPU hashing threads running (0 when stopped or GPU-only).
    public static var threads: Int { Int(b2m_threads()) }

    public static var isRunning: Bool { threads > 0 || gpu != nil }

    /// Why the GPU isn't hashing right now (e.g. Metal reported an error); nil if fine.
    public static var gpuProblem: String? { gpu?.problem }

    /// The hashing kernel this CPU uses, e.g. "NEON + SHA3 assembly".
    public static var kernel: String { String(cString: b2m_kernel()) }

    /// The most CPU threads the engine runs.
    public static let maxThreads = Int(B2M_MAX_CPU_THREADS)

    /// Hash of one 80-byte input via the optimized code path (self-test).
    static func hash80(_ input: Data) -> Data {
        var out = [UInt8](repeating: 0, count: 32)
        [UInt8](input).withUnsafeBufferPointer { b2m_hash80($0.baseAddress, &out) }
        return Data(out)
    }

    /// The GPU's name and the first word of the hash for `threads` × noncesPerThread
    /// nonces from `base`, from a separate GPUEngine instance (so it doesn't disturb
    /// GPU mining); nil if this Mac has no usable GPU.
    static func gpuDebugWords(input: Data, base: UInt64, threads: Int) -> (gpu: String, words: [UInt64]?)? {
        guard let gpu = try? GPUEngine(load: 100, responsive: false) else { return nil }
        return (gpu.deviceName, gpu.debugWords(input: input, base: base, threads: threads))
    }
}

/// Number of CPU cores, and how many are performance cores (Apple Silicon).
public enum CPUInfo {
    /// True when this process is Intel code translated by Rosetta on an Apple
    /// Silicon Mac: much slower, and macOS warns about it.
    public static var isTranslated: Bool {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        return sysctlbyname("sysctl.proc_translated", &value, &size, nil, 0) == 0 && value == 1
    }

    public static let rosettaWarning = "Running as Intel code under Rosetta: hashing is much slower, and macOS warns about it. Start BLAKE2b Miner normally (not with \"arch -x86_64\" or \"Open using Rosetta\") so it runs natively."

    public static var cores: Int { ProcessInfo.processInfo.activeProcessorCount }

    public static var performanceCores: Int {
        var n: Int32 = 0
        var size = MemoryLayout<Int32>.size
        if sysctlbyname("hw.perflevel0.logicalcpu", &n, &size, nil, 0) == 0, n > 0 { return Int(n) }
        return cores
    }
}
