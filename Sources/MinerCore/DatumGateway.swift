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
    private let lock = NSLock()
    private var _poolState = PoolState.none
    private var lastLines: [String] = []

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
        let configURL = try writeConfig()
        Self.killStale(configURL)
        let p = Process()
        p.executableURL = binary
        p.arguments = ["-c", configURL.path]
        p.currentDirectoryURL = Self.directory
        let pipe = Pipe()
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
        lock.unlock()
        try p.run()
        process = p
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
    }

    /// Gateway messages meaning the pool connection is in trouble.
    private static let poolProblemMarkers = ["connect(...) error", "Connection timed out", "No data received from server",
                                             "did NOT match", "Could not decrypt", "public key is invalid"]
    /// Gateway messages worth showing in the app log; the rest is routine.
    private static let importantMarkers = ["WARN", "ERROR", "FATAL", "MOTD", "BLOCK FOUND", "NEW NETWORK BLOCK",
                                           "Pool's public keys", "NON-POOLED"]

    /// A gateway left over from a crashed session would hold the Stratum port.
    private static func killStale(_ config: URL) {
        let pkill = Process()
        pkill.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        pkill.arguments = ["-f", "datum_gateway -c \(config.path)"]
        try? pkill.run()
        pkill.waitUntilExit()
        if pkill.terminationStatus == 0 { Thread.sleep(forTimeInterval: 1) }
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
        guard !line.isEmpty, !line.hasPrefix("*") else { return }
        lock.lock()
        lastLines.append(line)
        if lastLines.count > 20 { lastLines.removeFirst() }
        if line.contains("DATUM Server MOTD") || line.contains("DATUM connection resumed") {
            _poolState = .connected(pool?.name ?? "pool")
        } else if Self.poolProblemMarkers.contains(where: line.contains) {
            _poolState = .problem(line)
        }
        lock.unlock()
        if Self.importantMarkers.contains(where: line.contains) {
            log("[gateway] " + line.replacingOccurrences(of: "INFO: ", with: ""))
        }
    }

    private func writeConfig() throws -> URL {
        let dir = Self.directory
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
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
                "coinbase_tag_primary": "DATUM Gateway",
                "coinbase_tag_secondary": String(settings.coinbaseTag.prefix(40)),
            ],
            "api": ["listen_port": 0],
            "logger": ["log_to_console": true, "log_level_console": 2, "log_calling_function": false],
            "datum": datum,
        ]
        let url = dir.appendingPathComponent("gateway.json")
        let data = try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return url
    }
}
