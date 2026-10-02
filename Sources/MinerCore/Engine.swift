import CEngine
import Foundation

/// Thin wrapper around the C hashing engine (a process-wide singleton).
public enum Engine {
    public static func start(threads: Int, lowPriority: Bool) throws {
        guard b2m_start(Int32(threads), lowPriority ? 1 : 0) == 0 else {
            throw MinerError.config("Could not start \(threads) hashing threads")
        }
    }

    public static func stop() { b2m_stop() }

    /// - Parameters:
    ///   - input: the 80-byte final-stage input; bytes 32..39 are searched.
    ///   - target: solutions must hash to at most this value.
    public static func setWork(jobID: UInt64, input: Data, target: UInt256) {
        precondition(input.count == 80)
        let t = [UInt8](target.bigEndianData)
        [UInt8](input).withUnsafeBufferPointer { b2m_set_work(jobID, $0.baseAddress, t) }
    }

    public static func clearWork() { b2m_clear_work() }

    /// Returns (job id, the 8 solved bytes at offset 32 of the input).
    public static func takeSolution() -> (UInt64, Data)? {
        var job: UInt64 = 0
        var nonce = [UInt8](repeating: 0, count: 8)
        guard b2m_take_solution(&job, &nonce) == 1 else { return nil }
        return (job, Data(nonce))
    }

    public static var hashes: UInt64 { b2m_hashes() }

    public static var threads: Int { Int(b2m_threads()) }

    /// Hash of one 80-byte input via the optimized code path (self-test).
    static func hash80(_ input: Data) -> Data {
        var out = [UInt8](repeating: 0, count: 32)
        [UInt8](input).withUnsafeBufferPointer { b2m_hash80($0.baseAddress, &out) }
        return Data(out)
    }
}

/// Number of CPU cores, and how many are performance cores (Apple Silicon).
public enum CPUInfo {
    public static var cores: Int { ProcessInfo.processInfo.activeProcessorCount }

    public static var performanceCores: Int {
        var n: Int32 = 0
        var size = MemoryLayout<Int32>.size
        if sysctlbyname("hw.perflevel0.logicalcpu", &n, &size, nil, 0) == 0, n > 0 { return Int(n) }
        return cores
    }
}
