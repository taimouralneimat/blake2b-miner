import Foundation

/// Average number of hashes needed per unit of difficulty (difficulty 1 ≈ 2^32 hashes).
public let hashesPerDifficulty: Double = 4_294_967_296

public enum MiningMode: String, Codable, CaseIterable {
    /// Your own DATUM Gateway (bundled) next to your Knots node, pooling
    /// through a DATUM pool or solo.
    case datum
    /// Templates straight from a local Bitcoin Knots node; blocks pay your address.
    case solo
    /// A Stratum server: a pool's hosted gateway, or a gateway you run elsewhere.
    case stratum

    /// Whether your own node chooses the transactions and builds the blocks.
    /// With a hosted gateway the pool's node does.
    public var youBuildTheBlocks: Bool { self != .stratum }

    public var displayName: String {
        switch self {
        case .datum: return "your own DATUM Gateway"
        case .solo: return "solo mining with your node"
        case .stratum: return "a Stratum server"
        }
    }
}

public enum MinerState: Equatable {
    case stopped
    case starting
    case mining
    /// Running, but without work right now (node unreachable, paused on battery, ...).
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
    /// The block being mined (solo mode).
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
    public var server = ""
    /// DATUM mode: the pool connection, and who builds the blocks.
    public var gatewayStatus: String?
    public var lastError: String?

    public init() {}

    /// Average time to find one share at the current hashrate.
    public var expectedSecondsPerShare: Double? {
        guard let d = shareDifficulty, hashrate > 0 else { return nil }
        return d * hashesPerDifficulty / hashrate
    }
}

public struct FoundBlock: Codable {
    public static let accepted = "accepted"

    public var time: Date
    public var height: Int
    public var hash: String
    /// `FoundBlock.accepted`, or why the node rejected it.
    public var result: String
    public var blockHex: String?
    /// The node's chain ("main", "regtest", ...); nil in records from before 1.3.
    public var chain: String?

    public var isAccepted: Bool { result == Self.accepted }

    /// An accepted block on the real (main) chain: what "blocks found" counts.
    public var countsAsFound: Bool { isAccepted && (chain ?? "main") == "main" }
}

/// Receives log lines and status updates from a running miner, on its control thread.
public protocol MinerDelegate: AnyObject {
    func miner(log line: String)
    func miner(status: MinerStatus)
    func miner(found block: FoundBlock)
}

public func formatHashrate(_ rate: Double) -> String {
    var v = rate
    for unit in ["H/s", "kH/s", "MH/s", "GH/s", "TH/s"] {
        if v < 1000 || unit == "TH/s" { return String(format: v < 10 ? "%.2f %@" : "%.1f %@", v, unit) }
        v /= 1000
    }
    return ""
}

private let durationFormatter: NumberFormatter = {
    let f = NumberFormatter()
    f.numberStyle = .decimal
    return f
}()

public func formatDuration(_ seconds: Double) -> String {
    let units: [(String, Double)] = [("years", 31_557_600), ("days", 86400), ("hours", 3600), ("minutes", 60)]
    for (name, size) in units where seconds >= size {
        let n = seconds / size
        durationFormatter.maximumFractionDigits = n < 10 ? 1 : 0
        return "\(durationFormatter.string(from: NSNumber(value: n)) ?? "\(n)") \(name)"
    }
    return String(format: "%.0f seconds", seconds)
}

/// A share or network difficulty for display: whole numbers from 100 up
/// (pools often send values like 16383.75 for 16,384).
public func formatDifficulty(_ d: Double) -> String {
    d >= 100 ? d.rounded().formatted(.number.precision(.fractionLength(0))) : d.formatted(.number.precision(.significantDigits(3)))
}
