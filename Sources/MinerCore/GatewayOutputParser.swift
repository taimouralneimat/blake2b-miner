import Foundation

/// Interprets the DATUM Gateway's console output. It does no I/O: feed it
/// lines with `consume`, and read the pool and node state and found blocks.
struct GatewayOutputParser {
    enum PoolState: Equatable {
        case none
        case connecting
        case connected(String)
        case problem(String)
    }

    let poolName: String?
    /// "host:port" of the node, for messages.
    let nodeAddress: String

    private(set) var poolState: PoolState
    /// Since when the gateway has been unable to get block templates, if it still is.
    private(set) var templatesFailingSince: Date?
    /// The last few gateway lines, for error messages when it exits.
    private(set) var recentLines: [String] = []
    /// The gateway couldn't open its Stratum port: something else is listening on it.
    private(set) var portInUse = false
    /// The pool's verdicts on the shares the gateway forwarded (debug-level output).
    private(set) var poolAccepted = 0
    private(set) var poolRejected = 0
    private(set) var lastRejectReason: String?

    private var foundHashes: [String] = []
    private var poolResets: [Date] = []
    private var reportedIgnoredBlocks = Set<String>()

    init(poolName: String?, nodeAddress: String) {
        self.poolName = poolName
        self.nodeAddress = nodeAddress
        poolState = poolName == nil ? .none : .connecting
    }

    // MARK: Markers in the gateway's output

    /// A block the gateway solved: "BLOCK FOUND - <hash>", or, with a pool that uses
    /// anti-block-withholding (ABW), "revealed a verified block key for candidate <hash>".
    private static let blockFound = ["BLOCK FOUND", "revealed a verified block key for candidate"]
    /// The pool did not act on a valid block; the gateway logs this 8 times.
    private static let abwFailure = "CRITICAL ABW FAILURE"
    private static let templateFailure = "Could not fetch new template"
    private static let bindFailure = "bind failed"
    /// The gateway just got a fresh template from the node.
    private static let templateSuccess = ["Updating standard stratum job", "Updating priority stratum job", "NEW NETWORK BLOCK:"]
    private static let poolConnected = ["DATUM Server MOTD", "DATUM connection resumed"]
    private static let poolReset = ["reset by peer", "No data received from server"]
    private static let poolProblem = ["connect(...) error", "Connection timed out", "No data received from server",
                                      "did NOT match", "Could not decrypt", "public key is invalid"]
    /// Worth showing in the app log; everything else is routine.
    private static let important = ["WARN", "ERROR", "FATAL", "MOTD", "BLOCK FOUND", "NEW NETWORK BLOCK",
                                    "revealed a verified block", "Pool's public keys", "NON-POOLED"]
    /// The pool's answer to a forwarded share (the gateway logs these at debug level).
    private static let poolShareAccepted = "Share accepted: NONCE"
    private static let poolShareRejected = "DATUM server rejected our share"
    /// Routine lines that would only crowd the log: a harmless warning after a
    /// (re)start, and the notice the gateway prints twice for every network block.
    private static let noise = ["we did not see a new block", "NEW NETWORK BLOCK NOTIFICATION"]
    private static let networkBlock = "NEW NETWORK BLOCK:"

    private static let resetWindow: TimeInterval = 120
    private static let resetsForLoop = 3
    private static let recentLineCount = 20

    // MARK: Input

    /// Processes one line of gateway output; returns what to show in the app log.
    mutating func consume(_ raw: String, at now: Date = Date()) -> [String] {
        guard let line = Self.clean(raw) else { return [] }
        // Debug output is only read for the pool's verdicts on shares.
        if line.hasPrefix("DEBUG:") { return poolVerdict(line) }
        recentLines.append(line)
        if recentLines.count > Self.recentLineCount { recentLines.removeFirst() }

        var messages = [String]()
        if line.contains(Self.bindFailure) { portInUse = true }
        if Self.blockFound.contains(where: line.contains), let hash = Self.blockHash(in: line) {
            foundHashes.append(hash)
        }
        if line.contains(Self.abwFailure) {
            if let hash = Self.blockHash(in: line), reportedIgnoredBlocks.insert(hash).inserted {
                messages.append("ALERT: \(poolName ?? "The pool") did not act on a valid block you found (\(hash)). Your gateway submitted it to your node itself; consider another DATUM pool.")
            }
            return messages
        }
        if Self.poolReset.contains(where: line.contains) {
            poolResets.append(now)
            poolResets.removeAll { now.timeIntervalSince($0) > Self.resetWindow }
        }
        if Self.poolConnected.contains(where: line.contains) {
            if case .problem = poolState { messages.append("[gateway] Reconnected to \(poolName ?? "the pool")") }
            poolState = .connected(poolName ?? "pool")
        } else if Self.poolProblem.contains(where: line.contains) {
            poolState = .problem(line)
        }
        // While the node is unreachable the gateway logs the same error every
        // second: report it once, and once more when it recovers.
        if line.contains(Self.templateFailure) {
            if templatesFailingSince == nil {
                templatesFailingSince = now
                messages.append("[gateway] Can't get block templates from Bitcoin Knots at \(nodeAddress); retrying every second. Is Knots running?")
            }
            return messages
        }
        if let since = templatesFailingSince, Self.templateSuccess.contains(where: line.contains) {
            templatesFailingSince = nil
            messages.append("[gateway] Getting block templates from your node again (after \(Int(now.timeIntervalSince(since))) s)")
        }
        if Self.important.contains(where: line.contains), !Self.noise.contains(where: line.contains) {
            messages.append("[gateway] " + Self.readable(line))
        }
        return messages
    }

    private mutating func poolVerdict(_ line: String) -> [String] {
        let pool = poolName ?? "The pool"
        if line.contains(Self.poolShareAccepted) {
            poolAccepted += 1
            return ["[gateway] \(pool) accepted your share"]
        }
        guard line.contains(Self.poolShareRejected) else { return [] }
        poolRejected += 1
        let code = line.range(of: #"Reason code: \d+"#, options: .regularExpression)
            .flatMap { Int(line[$0].split(separator: " ").last ?? "") }
        let reason = code.map { "\(Self.rejectReason($0)) (code \($0))" } ?? "no reason given"
        lastRejectReason = reason
        return ["Problem: \(pool) rejected your share: \(reason)"]
    }

    /// DATUM share-rejection codes (datum_protocol.h), in plain words.
    static func rejectReason(_ code: Int) -> String {
        switch code {
        case 10: return "unknown job"
        case 11, 15, 22: return "the coinbase doesn't match the pool's"
        case 12: return "wrong extranonce size"
        case 13, 19: return "wrong share target"
        case 14: return "the username (payout address) isn't accepted"
        case 16: return "wrong merkle branch"
        case 17: return "the coinbase is too large"
        case 18: return "no coinbase"
        case 20, 21: return "the hash doesn't meet the target by the pool's calculation (the pool may not support BLAKE2b shares)"
        case 23: return "bad block time"
        case 24: return "bad block version"
        case 25: return "stale: the network moved on to a new block"
        case 26: return "the pool rejected the coinbase"
        case 27: return "the coinbase doesn't pay the pool's payout outputs"
        case 28: return "the pool's tag is missing from the coinbase"
        case 29: return "duplicate share"
        default: return "reason unknown"
        }
    }

    // MARK: Output

    /// Block hashes the gateway reported solving since the last call.
    mutating func takeFoundHashes() -> [String] {
        defer { foundHashes.removeAll() }
        return foundHashes
    }

    /// The pool keeps dropping the connection right after it's made: seen when the
    /// gateway keeps trying to resume a session the pool declines.
    func poolConnectionLooping(at now: Date = Date()) -> Bool {
        poolResets.filter { now.timeIntervalSince($0) <= Self.resetWindow }.count >= Self.resetsForLoop
    }

    // MARK: Helpers

    /// Strips the gateway's own timestamp and "[function]" prefix; nil for blank
    /// lines and its decorative "*****" banner lines.
    static func clean(_ raw: String) -> String? {
        var line = raw.trimmingCharacters(in: .whitespaces)
        if let r = line.range(of: #"^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d+\s+"#, options: .regularExpression) {
            line = String(line[r.upperBound...])
        }
        if let r = line.range(of: #"^\[[^\]]*\]\s+"#, options: .regularExpression) {
            line = String(line[r.upperBound...])
        }
        let message = line.replacingOccurrences(of: #"^[A-Z]+:\s*"#, with: "", options: .regularExpression)
        guard !message.isEmpty, !message.allSatisfy({ $0 == "*" || $0 == " " }) else { return nil }
        return line
    }

    /// "NEW NETWORK BLOCK: <hash> (<height>)" becomes "New network block 975723"; other
    /// lines lose their "INFO: " level.
    static func readable(_ line: String) -> String {
        if line.contains(networkBlock),
           let r = line.range(of: #"\((\d+)\)\s*$"#, options: .regularExpression) {
            return "New network block " + line[r].trimmingCharacters(in: CharacterSet(charactersIn: "() "))
        }
        return line.replacingOccurrences(of: "INFO: ", with: "")
    }

    private static func blockHash(in line: String) -> String? {
        line.range(of: #"[0-9a-f]{64}"#, options: .regularExpression).map { String(line[$0]) }
    }
}
