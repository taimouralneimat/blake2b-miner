import Foundation

/// Settings for the gateway the app runs next to your Knots node.
public struct GatewaySettings: Codable, Equatable {
    /// DatumPool id, or "" to mine solo through the gateway.
    public var poolID = "dxpool"
    public var stratumPort = 23334
    /// Listen on all interfaces so ASICs on your network can mine through it too.
    public var allowNetworkMiners = false
    /// When the pool is unreachable, keep mining solo (blocks pay 100% to you)
    /// instead of stopping.
    public var soloWhenPoolDown = true
    public var coinbaseTag = "BLAKE2b Miner"

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = GatewaySettings()
        poolID = c.decode(.poolID, or: d.poolID)
        stratumPort = c.decode(.stratumPort, or: d.stratumPort)
        allowNetworkMiners = c.decode(.allowNetworkMiners, or: d.allowNetworkMiners)
        soloWhenPoolDown = c.decode(.soloWhenPoolDown, or: d.soloWhenPoolDown)
        coinbaseTag = c.decode(.coinbaseTag, or: d.coinbaseTag)
    }
}

/// Runs the bundled CONVOY DATUM Gateway as a child process.
final class DatumGatewayProcess {
    enum PoolState: Equatable { case none, connecting, connected(String), problem(String) }

    let settings: GatewaySettings
    let node: NodeConfig
    let payoutAddress: String
    /// Receives the gateway's important log lines.
    var log: (String) -> Void = { _ in }
    private var process: Process?
    private var outputPipe: Pipe?
    private let lock = NSLock()
    private var _poolState = PoolState.none
    private var lastLines: [String] = []
    /// When the pool recently reset the connection, for spotting a reconnect loop.
    private var poolResets: [Date] = []

    /// Hashes of blocks the gateway reported solving, not yet picked up by `takeFoundBlocks()`.
    private var foundHashes: [String] = []

    /// Where the gateway saves every block it submits, for resubmitting by hand.
    static var submittedBlocksDirectory: URL { directory.appendingPathComponent("submitted-blocks", isDirectory: true) }

    /// When the gateway first failed to get a block template from the node, if it still is.
    private var templatesFailingSince: Date?

    init(settings: GatewaySettings, node: NodeConfig, payoutAddress: String) {
        self.settings = settings
        self.node = node
        self.payoutAddress = payoutAddress
    }

    var pool: DatumPool? { DatumPool.find(settings.poolID) }

    static var directory: URL { FoundBlocks.directory.appendingPathComponent("datum", isDirectory: true) }

    /// The gateway ships next to the app's executables (Contents/MacOS).
    static var binary: URL? {
        var candidates = [URL]()
        if let env = ProcessInfo.processInfo.environment["B2B_DATUM_GATEWAY"] { candidates.append(URL(fileURLWithPath: env)) }
        if let exe = Bundle.main.executableURL?.resolvingSymlinksInPath() {
            candidates.append(exe.deletingLastPathComponent().appendingPathComponent("datum_gateway"))
        }
        let argv0 = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        candidates.append(argv0.deletingLastPathComponent().appendingPathComponent("datum_gateway"))
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    var poolState: PoolState { lock.lock(); defer { lock.unlock() }; return _poolState }

    var isRunning: Bool { process?.isRunning == true }

    var stratumURL: String { "127.0.0.1:\(settings.stratumPort)" }

    func start() throws {
        guard let binary = Self.binary else {
            throw MinerError.config("The DATUM Gateway is missing from the app bundle. Please reinstall BLAKE2b Miner.")
        }
        guard (1...65535).contains(settings.stratumPort) else {
            throw MinerError.config("Invalid gateway Stratum port \(settings.stratumPort). Check Mining › Advanced in the dashboard.")
        }
        let configURL = try writeConfig()
        Self.stopStale()
        let p = Process()
        p.executableURL = binary
        p.arguments = ["-c", configURL.path]
        p.currentDirectoryURL = Self.directory
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        try? outputPipe?.fileHandleForReading.close()
        let pipe = Pipe()
        outputPipe = pipe
        p.standardOutput = pipe
        p.standardError = pipe
        var pending = Data()
        pipe.fileHandleForReading.readabilityHandler = { [weak self] h in
            let chunk = h.availableData
            guard !chunk.isEmpty else { h.readabilityHandler = nil; return }
            pending += chunk
            while let nl = pending.firstIndex(of: 0x0a) {
                let line = String(decoding: pending[pending.startIndex..<nl], as: UTF8.self)
                pending = Data(pending[(nl + 1)...])
                self?.handle(line)
            }
        }
        lock.lock()
        _poolState = pool == nil ? .none : .connecting
        lastLines = []
        templatesFailingSince = nil
        poolResets = []
        lock.unlock()
        try p.run()
        process = p
        try? String(p.processIdentifier).write(to: Self.pidFile, atomically: true, encoding: .utf8)
        log("Started your DATUM Gateway (Stratum on port \(settings.stratumPort)); "
            + (pool.map { "pooled mining with \($0.name), your node builds the blocks" } ?? "solo mining through the gateway"))
    }

    func stop() {
        guard let p = process else { return }
        process = nil
        if p.isRunning {
            p.terminate()
            let deadline = Date().addingTimeInterval(5)
            while p.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.1) }
            if p.isRunning { kill(p.processIdentifier, SIGKILL) }
        }
        try? FileManager.default.removeItem(at: Self.pidFile)
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        try? outputPipe?.fileHandleForReading.close()
        outputPipe = nil
    }

    /// Gateway messages meaning the pool connection is in trouble.
    private static let poolProblemMarkers = ["connect(...) error", "Connection timed out", "No data received from server",
                                             "did NOT match", "Could not decrypt", "public key is invalid"]
    /// Gateway messages that mean it just got a fresh template from the node.
    private static let templateSuccessMarkers = ["Updating standard stratum job", "Updating priority stratum job", "NEW NETWORK BLOCK:"]
    /// Harmless warnings the gateway prints after a (re)start; not worth alarming anyone.
    private static let noiseMarkers = ["we did not see a new block"]
    /// Gateway messages worth showing in the app log; the rest is routine.
    private static let importantMarkers = ["WARN", "ERROR", "FATAL", "MOTD", "BLOCK FOUND", "NEW NETWORK BLOCK",
                                           "Pool's public keys", "NON-POOLED"]

    private static var pidFile: URL { directory.appendingPathComponent("gateway.pid") }

    /// Stops a gateway left over from a crashed session (it would hold the
    /// Stratum port). Only a process that really is our datum_gateway is touched.
    private static func stopStale() {
        guard let text = try? String(contentsOf: pidFile, encoding: .utf8),
              let pid = pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines)), pid > 1 else { return }
        try? FileManager.default.removeItem(at: pidFile)
        var path = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        guard proc_pidpath(pid, &path, UInt32(path.count)) > 0,
              URL(fileURLWithPath: String(cString: path)).lastPathComponent == "datum_gateway" else { return }
        kill(pid, SIGTERM)
        for _ in 0..<50 where kill(pid, 0) == 0 { Thread.sleep(forTimeInterval: 0.1) }
        if kill(pid, 0) == 0 { kill(pid, SIGKILL) }
    }

    /// The pool keeps dropping the connection right after it's made. Seen when the
    /// gateway keeps trying to resume an old session that the pool declines;
    /// restarting the gateway starts a fresh session.
    var poolConnectionLooping: Bool {
        lock.lock(); defer { lock.unlock() }
        let now = Date()
        return poolResets.filter { now.timeIntervalSince($0) <= Self.resetWindow }.count >= Self.resetsForLoop
    }

    private static let resetWindow: TimeInterval = 120
    private static let resetsForLoop = 3

    /// Block hashes the gateway reported solving since the last call.
    func takeFoundBlocks() -> [String] {
        lock.lock(); defer { lock.unlock() }
        let hashes = foundHashes
        foundHashes.removeAll()
        return hashes
    }

    /// Set when the gateway has been unable to get block templates from the
    /// node for a while (a brief failure, e.g. while Knots restarts, is normal).
    var nodeProblem: String? {
        lock.lock(); defer { lock.unlock() }
        guard let since = templatesFailingSince, Date().timeIntervalSince(since) > 30 else { return nil }
        return "Your DATUM Gateway can't get block templates from Bitcoin Knots at \(node.host):\(node.port). Is Knots running, with its RPC server on?"
    }

    /// Last few gateway lines, for error messages when it exits.
    var recentOutput: String { lock.lock(); defer { lock.unlock() }; return lastLines.suffix(3).joined(separator: " | ") }

    private func handle(_ raw: String) {
        // "2026-10-02 22:51:19.312  INFO: message" -> "INFO: message" (the app log has its own timestamps)
        var line = raw.trimmingCharacters(in: .whitespaces)
        if let r = line.range(of: #"^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d+\s+"#, options: .regularExpression) {
            line = String(line[r.upperBound...])
        }
        if let r = line.range(of: #"^\[[^\]]*\]\s+"#, options: .regularExpression) { line = String(line[r.upperBound...]) }
        // Skip blank lines and the gateway's decorative "*****" banner lines.
        let message = line.replacingOccurrences(of: #"^[A-Z]+:\s*"#, with: "", options: .regularExpression)
        guard !message.isEmpty, !message.allSatisfy({ $0 == "*" || $0 == " " }) else { return }
        var recovered: [String] = []
        lock.lock()
        if line.contains("reset by peer") || line.contains("No data received from server") {
            let now = Date()
            poolResets.append(now)
            poolResets.removeAll { now.timeIntervalSince($0) > Self.resetWindow }
        }
        if line.contains("BLOCK FOUND"),
           let r = line.range(of: #"[0-9a-f]{64}"#, options: .regularExpression) {
            foundHashes.append(String(line[r]))
        }
        lastLines.append(line)
        if lastLines.count > 20 { lastLines.removeFirst() }
        if line.contains("DATUM Server MOTD") || line.contains("DATUM connection resumed") {
            if case .problem = _poolState { recovered.append("Reconnected to \(pool?.name ?? "the pool")") }
            _poolState = .connected(pool?.name ?? "pool")
        } else if Self.poolProblemMarkers.contains(where: line.contains) {
            _poolState = .problem(line)
        }
        // The gateway retries every second while the node is unreachable, logging
        // the same error each time: report it once, and once when it recovers.
        var suppress = false
        if line.contains("Could not fetch new template") {
            suppress = true
            if templatesFailingSince == nil {
                templatesFailingSince = Date()
                recovered.append("Can't get block templates from Bitcoin Knots at \(node.host):\(node.port); retrying every second. Is Knots running?")
            }
        } else if Self.templateSuccessMarkers.contains(where: line.contains), let since = templatesFailingSince {
            templatesFailingSince = nil
            recovered.append("Getting block templates from your node again (after \(Int(Date().timeIntervalSince(since))) s)")
        }
        lock.unlock()
        for message in recovered { log("[gateway] " + message) }
        if suppress { return }
        if Self.importantMarkers.contains(where: line.contains), !Self.noiseMarkers.contains(where: line.contains) {
            log("[gateway] " + line.replacingOccurrences(of: "INFO: ", with: ""))
        }
    }

    private func writeConfig() throws -> URL {
        let dir = Self.directory
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try FileManager.default.createDirectory(at: Self.submittedBlocksDirectory, withIntermediateDirectories: true)
        var bitcoind: [String: Any] = ["rpcurl": "http://\(node.host):\(node.port)", "notify_fallback": true, "work_update_seconds": 40]
        if !node.rpcUser.isEmpty {
            bitcoind["rpcuser"] = node.rpcUser
            bitcoind["rpcpassword"] = node.rpcPassword
        } else {
            guard let cookie = node.cookiePaths.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
                throw MinerError.config("No RPC cookie found in \(node.resolvedDataDir). Is Bitcoin Knots running with server=1?")
            }
            bitcoind["rpccookiefile"] = cookie
        }
        var datum: [String: Any] = ["pool_host": "", "pooled_mining_only": false]
        if let pool = pool {
            datum = [
                "pool_host": pool.host,
                "pool_port": pool.port,
                "pool_pubkey": pool.pubkey,
                "pool_pass_workers": true,
                "pool_pass_full_users": true,
                "pooled_mining_only": !settings.soloWhenPoolDown,
            ]
        }
        let config: [String: Any] = [
            "bitcoind": bitcoind,
            "stratum": [
                "listen_addr": settings.allowNetworkMiners ? "" : "127.0.0.1",
                "listen_port": settings.stratumPort,
                // CPU-friendly floor; a pool's own minimum still applies when pooled.
                "vardiff_min": 1,
                "idle_timeout_no_shares": 0,
            ],
            "mining": [
                "pool_address": payoutAddress,
                "save_submitblocks_dir": Self.submittedBlocksDirectory.path,
                "coinbase_tag_primary": "DATUM Gateway",
                "coinbase_tag_secondary": String(settings.coinbaseTag.prefix(40)),
            ],
            "api": ["listen_port": 0],
            "logger": ["log_to_console": true, "log_level_console": 2, "log_calling_function": false],
            "datum": datum,
        ]
        // The file can contain the RPC password, so it is created readable by
        // this user only, then moved into place.
        let url = dir.appendingPathComponent("gateway.json")
        let temp = dir.appendingPathComponent(".gateway.json.\(getpid())")
        let data = try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys])
        guard FileManager.default.createFile(atPath: temp.path, contents: data, attributes: [.posixPermissions: 0o600]) else {
            throw MinerError.config("Could not write the DATUM Gateway configuration in \(dir.path)")
        }
        guard rename(temp.path, url.path) == 0 else {
            try? FileManager.default.removeItem(at: temp)
            throw MinerError.config("Could not write the DATUM Gateway configuration in \(dir.path)")
        }
        return url
    }
}
