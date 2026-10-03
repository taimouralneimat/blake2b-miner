import Foundation

public enum MinerError: Error, LocalizedError {
    case rpc(String)
    case connection(String)
    case config(String)
    case protocolError(String)

    public var errorDescription: String? {
        switch self {
        case .rpc(let m), .connection(let m), .config(let m), .protocolError(let m): return m
        }
    }
}

/// How to reach a Bitcoin Knots node's JSON-RPC interface.
public struct NodeConfig: Codable, Equatable {
    public var host = "127.0.0.1"
    public var port = 8332
    /// Data directory holding `.cookie`. Empty means the default for this Mac.
    public var dataDir = ""
    /// Optional `rpcuser`/`rpcpassword`; used instead of the cookie when set.
    public var rpcUser = ""
    public var rpcPassword = ""

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = NodeConfig()
        host = c.decode(.host, or: d.host)
        port = c.decode(.port, or: d.port)
        dataDir = c.decode(.dataDir, or: d.dataDir)
        rpcUser = c.decode(.rpcUser, or: d.rpcUser)
        rpcPassword = c.decode(.rpcPassword, or: d.rpcPassword)
    }

    public static var defaultDataDir: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Bitcoin").path
    }

    public var resolvedDataDir: String { dataDir.isEmpty ? Self.defaultDataDir : (dataDir as NSString).expandingTildeInPath }

    /// Where bitcoind may have written its cookie: the main data directory and
    /// each chain's subdirectory, the one matching a standard port first.
    var cookiePaths: [String] {
        let base = URL(fileURLWithPath: resolvedDataDir)
        let byPort: [Int: String] = [18332: "testnet3", 48332: "testnet4", 38332: "signet", 18443: "regtest"]
        var dirs = [base]
        for sub in ["testnet3", "testnet4", "signet", "regtest"] { dirs.append(base.appendingPathComponent(sub)) }
        if let s = byPort[port] { dirs.insert(base.appendingPathComponent(s), at: 0) }
        return dirs.map { $0.appendingPathComponent(".cookie").path }
    }
}

/// Minimal synchronous JSON-RPC client. Rereads the cookie when the node restarts.
public final class NodeRPC {
    public let config: NodeConfig
    private var authHeader: String?
    private let session: URLSession

    public init(_ config: NodeConfig, timeout: TimeInterval = 60) {
        self.config = config
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = timeout
        c.httpMaximumConnectionsPerHost = 2
        session = URLSession(configuration: c)
    }

    private func loadAuth() throws -> String {
        if !config.rpcUser.isEmpty {
            return "Basic " + Data("\(config.rpcUser):\(config.rpcPassword)".utf8).base64EncodedString()
        }
        for path in config.cookiePaths {
            if let cookie = try? String(contentsOfFile: path, encoding: .utf8) {
                return "Basic " + Data(cookie.trimmingCharacters(in: .whitespacesAndNewlines).utf8).base64EncodedString()
            }
        }
        throw MinerError.config("No RPC cookie found in \(config.resolvedDataDir). Is Bitcoin Knots running with server=1? "
            + "If it uses a custom data directory, set it in Settings, or set an RPC user and password.")
    }

    @discardableResult
    public func call(_ method: String, _ params: [Any] = [], wallet: String? = nil) throws -> Any {
        for attempt in 0..<2 {
            if authHeader == nil || attempt == 1 { authHeader = try loadAuth() }
            var url = URLComponents()
            url.scheme = "http"
            url.host = config.host
            url.port = config.port
            url.path = wallet.map { "/wallet/" + $0 } ?? "/"
            var req = URLRequest(url: url.url!)
            req.httpMethod = "POST"
            req.setValue(authHeader, forHTTPHeaderField: "Authorization")
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: ["jsonrpc": "1.0", "id": 1, "method": method, "params": params])

            let (data, response, error) = synchronous(req)
            if let error = error {
                throw MinerError.connection("Cannot reach the node at \(config.host):\(config.port) (\(error.localizedDescription)). Is Bitcoin Knots running with server=1?")
            }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 401 {
                if attempt == 0 && config.rpcUser.isEmpty { continue }  // node restarted: new cookie
                throw MinerError.connection("The node rejected the RPC credentials.")
            }
            guard let data = data, let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw MinerError.rpc("\(method): unexpected reply (HTTP \(status))")
            }
            if let err = obj["error"] as? [String: Any] {
                throw MinerError.rpc("\(method): \(err["message"] as? String ?? "\(err)")")
            }
            return obj["result"] ?? NSNull()
        }
        throw MinerError.connection("RPC authentication failed")
    }

    private func synchronous(_ req: URLRequest) -> (Data?, URLResponse?, Error?) {
        let sem = DispatchSemaphore(value: 0)
        var result: (Data?, URLResponse?, Error?) = (nil, nil, nil)
        session.dataTask(with: req) { d, r, e in
            result = (d, r, e)
            sem.signal()
        }.resume()
        sem.wait()
        return result
    }
}
