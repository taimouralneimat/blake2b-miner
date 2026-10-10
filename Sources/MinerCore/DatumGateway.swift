import Foundation

/// Settings for the gateway the app runs next to your Knots node.
public struct GatewaySettings: Codable, Equatable {
    /// A DatumPool id (built-in or in `customPools`), or "" to mine solo through the gateway.
    public var poolID = "lazarus"
    /// DATUM pools you added yourself.
    public var customPools: [DatumPool] = []
    public var stratumPort = 23334
    /// Listen on all interfaces so ASICs on your network can mine through it too.
    public var allowNetworkMiners = false
    /// When the pool is unreachable, keep mining solo (blocks pay 100% to you)
    /// instead of stopping.
    public var soloWhenPoolDown = true
    public var coinbaseTag = "BLAKE2b Miner"

    public init() {}

    /// Every pool to choose from: the built-in ones, then yours.
    public var pools: [DatumPool] { DatumPool.all + customPools }

    /// The chosen pool; nil to mine solo through the gateway.
    public var pool: DatumPool? { pools.first { $0.id == poolID } }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = GatewaySettings()
        poolID = c.decode(.poolID, or: d.poolID)
        customPools = c.decode(.customPools, or: d.customPools)
        // A pool that is no longer built in stays chosen, as a custom pool.
        if let retired = DatumPool.retired.first(where: { $0.id == poolID }), !customPools.contains(where: { $0.id == poolID }) {
            customPools.append(retired)
        }
        stratumPort = c.decode(.stratumPort, or: d.stratumPort)
        allowNetworkMiners = c.decode(.allowNetworkMiners, or: d.allowNetworkMiners)
        soloWhenPoolDown = c.decode(.soloWhenPoolDown, or: d.soloWhenPoolDown)
        coinbaseTag = c.decode(.coinbaseTag, or: d.coinbaseTag)
    }
}

/// Runs the bundled CONVOY DATUM Gateway as a child process. Its output is
/// interpreted by `GatewayOutputParser`.
final class DatumGatewayProcess {
    typealias PoolState = GatewayOutputParser.PoolState

    let settings: GatewaySettings
    let node: NodeConfig
    let payoutAddress: String
    /// Receives the gateway's log lines worth showing.
    var log: (String) -> Void = { _ in }
    private var process: Process?
    private var outputPipe: Pipe?
    /// Guarded by `lock`: output arrives on a background thread.
    private var parser: GatewayOutputParser
    private let lock = NSLock()

    /// How long the node may be unreachable before it counts as a problem
    /// (a short outage, e.g. while Knots restarts, is normal).
    private static let nodeOutageGrace: TimeInterval = 30

    init(settings: GatewaySettings, node: NodeConfig, payoutAddress: String) {
        self.settings = settings
        self.node = node
        self.payoutAddress = payoutAddress
        parser = GatewayOutputParser(poolName: settings.pool?.name, nodeAddress: "\(node.host):\(node.port)")
    }

    var pool: DatumPool? { settings.pool }

    static var directory: URL { FoundBlocks.directory.appendingPathComponent("datum", isDirectory: true) }

    /// Where the gateway saves every block it submits, for resubmitting by hand.
    static var submittedBlocksDirectory: URL { directory.appendingPathComponent("submitted-blocks", isDirectory: true) }

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

    var isRunning: Bool { process?.isRunning == true }

    var stratumURL: String { "127.0.0.1:\(settings.stratumPort)" }

    // MARK: State from the gateway's output

    private func withParser<T>(_ body: (inout GatewayOutputParser) -> T) -> T {
        lock.lock(); defer { lock.unlock() }
        return body(&parser)
    }

    var poolState: PoolState { withParser { $0.poolState } }

    /// The pool keeps dropping the connection; restarting the gateway starts a fresh session.
    var poolConnectionLooping: Bool { withParser { $0.poolConnectionLooping() } }

    /// Block hashes the gateway reported solving since the last call.
    func takeFoundBlocks() -> [String] { withParser { $0.takeFoundHashes() } }

    /// Set when the gateway has been unable to get block templates from the node for a while.
    var nodeProblem: String? {
        guard let since = withParser({ $0.templatesFailingSince }),
              Date().timeIntervalSince(since) > Self.nodeOutageGrace else { return nil }
        return "Your DATUM Gateway can't get block templates from Bitcoin Knots at \(node.host):\(node.port). Is Knots running, with its RPC server on?"
    }

    /// The last few gateway lines, for error messages when it exits.
    var recentOutput: String { withParser { $0.recentLines.suffix(3).joined(separator: " | ") } }
    var portInUse: Bool { withParser { $0.portInUse } }
    /// The pool's verdicts on forwarded shares so far: accepted, rejected, the last reason.
    var poolShareResults: (accepted: Int, rejected: Int, reason: String?) {
        withParser { ($0.poolAccepted, $0.poolRejected, $0.lastRejectReason) }
    }

    private func handle(_ raw: String) {
        let messages = withParser { $0.consume(raw) }
        messages.forEach(log)
    }

    // MARK: Process

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
        attachOutput(of: p)
        lock.lock()
        parser = GatewayOutputParser(poolName: pool?.name, nodeAddress: "\(node.host):\(node.port)")
        lock.unlock()
        try p.run()
        process = p
        try? String(p.processIdentifier).write(to: Self.pidFile, atomically: true, encoding: .utf8)
        log("Started your DATUM Gateway (Stratum on port \(settings.stratumPort)); "
            + (pool.map { "pooled mining with \($0.name), your node builds the blocks" } ?? "solo mining through the gateway"))
    }

    /// Feeds the process's stdout and stderr, line by line, to `handle`.
    private func attachOutput(of p: Process) {
        closeOutput()
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
    }

    private func closeOutput() {
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        try? outputPipe?.fileHandleForReading.close()
        outputPipe = nil
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
        closeOutput()
    }

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

    // MARK: Configuration

    /// Writes gateway.json and returns its location.
    private func writeConfig() throws -> URL {
        let dir = Self.directory
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try FileManager.default.createDirectory(at: Self.submittedBlocksDirectory, withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: try configuration(), options: [.prettyPrinted, .sortedKeys])
        let url = dir.appendingPathComponent("gateway.json")
        try Self.writePrivately(data, to: url)
        return url
    }

    /// The gateway's configuration (see `datum_gateway --help`).
    private func configuration() throws -> [String: Any] {
        [
            "bitcoind": try nodeSection(),
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
            "api": ["listen_port": 0],  // no web dashboard
            // Debug level: the pool's verdict on each share is only logged there (the parser
            // reads those lines and drops the rest).
            "logger": ["log_to_console": true, "log_level_console": 1, "log_calling_function": false],
            "datum": poolSection(),
        ]
    }

    /// How the gateway reaches the node: RPC user and password, or the cookie file.
    private func nodeSection() throws -> [String: Any] {
        var section: [String: Any] = ["rpcurl": "http://\(node.host):\(node.port)", "notify_fallback": true, "work_update_seconds": 40]
        if !node.rpcUser.isEmpty {
            section["rpcuser"] = node.rpcUser
            section["rpcpassword"] = node.rpcPassword
        } else {
            guard let cookie = node.cookiePaths.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
                throw MinerError.config("No RPC cookie found in \(node.resolvedDataDir). Is Bitcoin Knots running with server=1?")
            }
            section["rpccookiefile"] = cookie
        }
        return section
    }

    /// The DATUM pool to join, authenticated by its public key, or none for solo.
    private func poolSection() -> [String: Any] {
        guard let pool = pool else { return ["pool_host": "", "pooled_mining_only": false] }
        return [
            "pool_host": pool.host,
            "pool_port": pool.port,
            "pool_pubkey": pool.pubkey.lowercased(),
            "pool_pass_workers": true,
            "pool_pass_full_users": true,
            "pooled_mining_only": !settings.soloWhenPoolDown,
        ]
    }

    /// The configuration can contain the RPC password, so it is created readable
    /// by this user only, then renamed into place atomically.
    private static func writePrivately(_ data: Data, to url: URL) throws {
        let temp = url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).\(getpid())")
        let failure = MinerError.config("Could not write the DATUM Gateway configuration in \(url.deletingLastPathComponent().path)")
        guard FileManager.default.createFile(atPath: temp.path, contents: data, attributes: [.posixPermissions: 0o600]) else { throw failure }
        guard rename(temp.path, url.path) == 0 else {
            try? FileManager.default.removeItem(at: temp)
            throw failure
        }
    }
}
