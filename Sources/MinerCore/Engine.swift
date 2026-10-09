import CEngine
import Foundation

/// The hashing engines: CPU threads (the C engine) and, optionally, the GPU
/// (`GPUEngine`). Work goes to both; solutions and hash counts come from both.
/// A process-wide singleton.
public enum Engine {
    private static let lock = NSLock()
    private static var gpuEngine: GPUEngine?

    /// Starts CPU hashing threads (idle until work is set).
    public static func start(threads: Int, lowPriority: Bool) throws {
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
        let old = gpuEngine
        gpuEngine = gpu
        lock.unlock()
        old?.stop()
        gpu.start()
        return gpu.deviceName
    }

    /// Stops the CPU threads and the GPU.
    public static func stop() {
        b2m_stop()
        lock.lock()
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

    /// The GPU kernel against the reference BLAKE2b on `threads` × 16 nonces; nil if
    /// this Mac has no usable GPU. Runs its own GPU engine, so it works while mining.
    static func checkGPU(input: Data, threads: Int) throws -> (gpu: String, checked: Int)? {
        guard let gpu = try? GPUEngine(load: 100, responsive: false) else { return nil }
        let base = GPUEngine.firstNonce + 12_345
        guard let words = gpu.debugWords(input: input, base: base, threads: threads) else {
            throw MinerError.config("the GPU didn't run the kernel")
        }
        var bytes = [UInt8](input)
        for (i, word) in words.enumerated() {
            let nonce = base + UInt64(i)
            withUnsafeBytes(of: nonce.littleEndian) { bytes.replaceSubrange(32..<40, with: $0) }
            let ref = Hash.blake2b256(Data(bytes))
            let refWord = ref.prefix(8).enumerated().reduce(UInt64(0)) { $0 | UInt64($1.element) << (8 * UInt64($1.offset)) }
            guard word == refWord else {
                throw MinerError.config("GPU hash mismatch at nonce \(String(nonce, radix: 16))")
            }
        }
        return (gpu.deviceName, words.count)
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
