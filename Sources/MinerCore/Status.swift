import Foundation

public enum MiningMode: String, Codable, CaseIterable {
    /// Your own DATUM Gateway (bundled) next to your Knots node: you build the
    /// blocks, optionally pooling through a DATUM pool.
    case datum
    /// Templates straight from a local Bitcoin Knots node; blocks pay your address.
    case solo
    /// A Stratum server: a pool's hosted gateway (the pool builds the blocks)
    /// or a gateway you run elsewhere.
    case stratum
}

public enum MinerState: Equatable {
    case stopped
    case starting
    case mining
    /// Running, but no work right now (node unreachable, paused on battery, ...).
    case waiting(String)
}

/// A snapshot for display. Rates are hashes per second.
public struct MinerStatus {
    public var state: MinerState = .stopped
    public var mode: MiningMode = .solo
    public var hashrate: Double = 0
    public var averageHashrate: Double = 0
    public var totalHashes: UInt64 = 0
    public var threads = 0
    public var startedAt: Date?
    /// Height being mined and the network target (solo mode).
    public var height: Int?
    public var networkDifficulty: Double?
    public var expectedSecondsPerBlock: Double?
    public var transactions: Int?
    public var reward: Double?
    /// Stratum share counters and the current share difficulty.
    public var sharesAccepted = 0
    public var sharesRejected = 0
    public var shareDifficulty: Double?
    public var blocksFound = 0
    public var server: String = ""
    /// DATUM mode: who builds the blocks and the pool connection state.
    public var gatewayStatus: String?
    public var lastError: String?

    public init() {}
}

public struct FoundBlock: Codable {
    public var time: Date
    public var height: Int
    public var hash: String
    public var result: String
    public var blockHex: String?
}

/// Receives log lines and status updates from a running miner (on its control thread).
public protocol MinerDelegate: AnyObject {
    func miner(log line: String)
    func miner(status: MinerStatus)
    func miner(found block: FoundBlock)
}

public func formatHashrate(_ r: Double) -> String {
    var v = r
    for unit in ["H/s", "kH/s", "MH/s", "GH/s", "TH/s"] {
        if v < 1000 || unit == "TH/s" { return String(format: v < 10 ? "%.2f %@" : "%.1f %@", v, unit) }
        v /= 1000
    }
    return ""
}

public func formatDuration(_ s: Double) -> String {
    let units: [(String, Double)] = [("years", 31_557_600), ("days", 86400), ("hours", 3600), ("minutes", 60)]
    for (name, size) in units where s >= size {
        let n = s / size
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = n < 10 ? 1 : 0
        return "\(f.string(from: NSNumber(value: n)) ?? "\(n)") \(name)"
    }
    return String(format: "%.0f seconds", s)
}
