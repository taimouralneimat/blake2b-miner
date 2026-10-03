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
    /// The gateway just got a fresh template from the node.
    private static let templateSuccess = ["Updating standard stratum job", "Updating priority stratum job", "NEW NETWORK BLOCK:"]
    private static let poolConnected = ["DATUM Server MOTD", "DATUM connection resumed"]
    private static let poolReset = ["reset by peer", "No data received from server"]
    private static let poolProblem = ["connect(...) error", "Connection timed out", "No data received from server",
                                      "did NOT match", "Could not decrypt", "public key is invalid"]
    /// Worth showing in the app log; everything else is routine.
    private static let important = ["WARN", "ERROR", "FATAL", "MOTD", "BLOCK FOUND", "NEW NETWORK BLOCK",
                                    "revealed a verified block", "Pool's public keys", "NON-POOLED"]
    /// Harmless warnings the gateway prints after a (re)start.
    private static let noise = ["we did not see a new block"]

    private static let resetWindow: TimeInterval = 120
    private static let resetsForLoop = 3
    private static let recentLineCount = 20

    // MARK: Input

    /// Processes one line of gateway output; returns what to show in the app log.
    mutating func consume(_ raw: String, at now: Date = Date()) -> [String] {
        guard let line = Self.clean(raw) else { return [] }
        recentLines.append(line)
        if recentLines.count > Self.recentLineCount { recentLines.removeFirst() }

        var messages = [String]()
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
            messages.append("[gateway] " + line.replacingOccurrences(of: "INFO: ", with: ""))
        }
        return messages
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

    private static func blockHash(in line: String) -> String? {
        line.range(of: #"[0-9a-f]{64}"#, options: .regularExpression).map { String(line[$0]) }
    }
}
