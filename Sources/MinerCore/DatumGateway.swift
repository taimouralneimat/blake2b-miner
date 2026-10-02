import Foundation

/// A DATUM pool that your own gateway can connect to. With DATUM your node
/// builds the block templates; the pool only coordinates payouts.
/// Each entry was verified by completing the encrypted DATUM handshake with
/// the bundled gateway; the public key authenticates the pool.
public struct DatumPool: Identifiable, Hashable {
    public let id: String
    public let name: String
    public let host: String
    public let port: Int
    public let pubkey: String
    public let fee: String
    public let website: String

    public static let all: [DatumPool] = [
        DatumPool(id: "dxpool", name: "DXPool", host: "xbt.datum.dxpool.com", port: 28915,
                  pubkey: "13dceb1f532408e88661e613c017e88becf0f0e0f3c06fcbb457b49a5033fe427326610133e943af4d3d0fd083a5b18c93f4364c26e3d71472cfe7dbf0ee5514",
                  fee: "see dxpool.net", website: "https://www.dxpool.net/help/en/tutorial/dxpool-datum-gateway-mining/"),
        DatumPool(id: "xorpool", name: "Xor Pool", host: "datum.xorpool.com", port: 28915,
                  pubkey: "b83aedbba54ba2aa605c76859d97aebd16dece3284402b9fc874778a974da4acbb449f6ccda61625d700036f0487a05f5184f79a07abf2880da77352f4cc487e",
                  fee: "1%", website: "https://xorpool.com"),
        DatumPool(id: "convoy", name: "CONVOY", host: "datum-beta1.mine.convoy.xyz", port: 28915,
                  pubkey: "dbb11fa0c2b5403e4f798fa6071bb97e6079d219598366032fdf2ae01962b13c5e66e2be7d6b008f0b2603f3e6f6fc64768fa786c8129c46d3e30a5867734b62",
                  fee: "1%", website: "https://convoy.xyz"),
        DatumPool(id: "tyger", name: "Tyger Pool", host: "tygerpool.com", port: 28915,
                  pubkey: "8918e6a6437f9238118da5ce657f90b866dd4d31820d07e798ccd1b8986804ae36d1e494e919fa5e0ba251aec1c631e260f89628ebe6ebafc4b276554f295c3f",
                  fee: "0% (launch)", website: "https://tygerpool.com"),
    ]

    public static func find(_ id: String) -> DatumPool? { all.first { $0.id == id } }
}

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
        func get<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T { (try? c.decodeIfPresent(T.self, forKey: key)) ?? fallback }
        let d = GatewaySettings()
        poolID = get(.poolID, d.poolID)
        stratumPort = get(.stratumPort, d.stratumPort)
        allowNetworkMiners = get(.allowNetworkMiners, d.allowNetworkMiners)
        soloWhenPoolDown = get(.soloWhenPoolDown, d.soloWhenPoolDown)
        coinbaseTag = get(.coinbaseTag, d.coinbaseTag)
    }
}

/// Runs the bundled CONVOY DATUM Gateway as a child process.
final class DatumGatewayProcess {
    enum PoolState: Equatable { case none, connecting, connected(String), problem(String) }

    let settings: GatewaySettings
    let node: NodeConfig
    let payoutAddress: String
    private let log: (String) -> Void
    private var process: Process?
    private let lock = NSLock()
    private var _poolState = PoolState.none
    private var lastLines: [String] = []

    init(settings: GatewaySettings, node: NodeConfig, payoutAddress: String, log: @escaping (String) -> Void) {
        self.settings = settings
        self.node = node
        self.payoutAddress = payoutAddress
        self.log = log
    }

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
        _poolState = DatumPool.find(settings.poolID) == nil ? .none : .connecting
        lastLines = []
        lock.unlock()
        try p.run()
        process = p
        let pool = DatumPool.find(settings.poolID)
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
            _poolState = .connected(DatumPool.find(settings.poolID)?.name ?? "pool")
        } else if line.contains("connect(...) error") || line.contains("Connection timed out")
                    || line.contains("No data received from server") || line.contains("did NOT match")
                    || line.contains("Could not decrypt") || line.contains("public key is invalid") {
            _poolState = .problem(line)
        }
        lock.unlock()
        // Keep the app log readable: warnings, errors and the important info lines.
        let important = ["WARN", "ERROR", "FATAL", "MOTD", "BLOCK FOUND", "NEW NETWORK BLOCK", "Pool's public keys", "NON-POOLED"]
        if important.contains(where: line.contains) {
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
        if let pool = DatumPool.find(settings.poolID) {
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
