import Foundation
import Network

public struct StratumConfig: Codable, Equatable {
    /// "host:port", "stratum+tcp://host:port" or "stratum+ssl://host:port" (TLS).
    /// A DATUM Gateway listens on 23334 by default.
    public var url = "127.0.0.1:23334"
    /// Worker name; pools expect your payout address, optionally followed by ".worker".
    public var user = ""
    public var password = "x"

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = StratumConfig()
        url = c.decode(.url, or: d.url)
        user = c.decode(.user, or: d.user)
        password = c.decode(.password, or: d.password)
    }

    public struct Endpoint {
        public let host: String
        public let port: UInt16
        public let tls: Bool
    }

    public func endpoint() throws -> Endpoint {
        var s = url.trimmingCharacters(in: .whitespaces)
        var tls = false
        if let r = s.range(of: "://") {
            let scheme = s[..<r.lowerBound].lowercased()
            tls = scheme.hasSuffix("ssl") || scheme.hasSuffix("tls")
            s = String(s[r.upperBound...])
        }
        if s.hasSuffix("/") { s.removeLast() }
        guard let colon = s.lastIndex(of: ":"), let port = UInt16(s[s.index(after: colon)...]), port > 0, !s[..<colon].isEmpty else {
            throw MinerError.config("The Stratum server must look like host:port, e.g. 127.0.0.1:23334 (got \"\(url)\")")
        }
        var host = String(s[..<colon])
        if host.hasPrefix("[") && host.hasSuffix("]") { host = String(host.dropFirst().dropLast()) }  // [IPv6]:port
        return Endpoint(host: host, port: port, tls: tls)
    }
}

/// One line-delimited JSON Stratum connection. Received messages queue up in an
/// inbox that the owner drains from its own thread.
final class StratumConnection {
    enum State { case connecting, open, closed(String?) }

    private let queue = DispatchQueue(label: "stratum.connection")
    private let lock = NSLock()
    private let connection: NWConnection
    private var buffer = Data()
    private var inbox: [[String: Any]] = []
    private var _state = State.connecting

    init(_ endpoint: StratumConfig.Endpoint) {
        let params: NWParameters = endpoint.tls ? .tls : .tcp
        connection = NWConnection(host: NWEndpoint.Host(endpoint.host), port: NWEndpoint.Port(rawValue: endpoint.port)!, using: params)
    }

    var state: State { lock.lock(); defer { lock.unlock() }; return _state }

    var isClosed: Bool { if case .closed = state { return true }; return false }

    /// Connects, then subscribes (request id 1) and authorizes (id 2).
    func start(user: String, password: String) {
        connection.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .ready:
                self.set(.open)
                self.send(["id": 1, "method": "mining.subscribe", "params": [Miner.userAgent]])
                self.send(["id": 2, "method": "mining.authorize", "params": [user, password]])
                self.receive()
            case .failed(let error), .waiting(let error):
                self.close("connection failed: \(error.localizedDescription)")
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    func send(_ obj: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: obj) else { return }
        connection.send(content: data + Data([0x0a]), completion: .contentProcessed { _ in })
    }

    func drain() -> [[String: Any]] {
        lock.lock(); defer { lock.unlock() }
        let m = inbox
        inbox.removeAll()
        return m
    }

    func close(_ reason: String?) {
        lock.lock()
        if case .closed = _state { lock.unlock(); return }
        _state = .closed(reason)
        lock.unlock()
        connection.cancel()
    }

    private func set(_ s: State) { lock.lock(); _state = s; lock.unlock() }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, done, error in
            guard let self = self else { return }
            if let data = data, !data.isEmpty {
                self.buffer += data
                while let nl = self.buffer.firstIndex(of: 0x0a) {
                    let line = self.buffer[self.buffer.startIndex..<nl]
                    self.buffer = Data(self.buffer[(nl + 1)...])
                    if let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any] {
                        self.lock.lock(); self.inbox.append(obj); self.lock.unlock()
                    }
                }
                if self.buffer.count > 1 << 20 { self.close("server sent an oversized message"); return }
            }
            if done || error != nil {
                self.close(error.map { "connection lost: \($0.localizedDescription)" } ?? "server closed the connection")
            } else {
                self.receive()
            }
        }
    }
}

/// A BLAKE2b header-v2 job from `mining.notify`, in the DATUM Gateway's ("Sia-style") dialect:
///
///   [job_id, prevhash, coinb1, coinb2, merkle_branch, version, nbits, ntime, clean_jobs]
///     prevhash  32-byte hidden previous-block value, raw hex
///     nbits     compact share target
///     ntime     8 bytes (time_offset | nonce3), raw hex
///   root  = BLAKE2b-256(0x00 || coinb1 || extranonce1 || extranonce2 || coinb2)
///   input = prevhash || nonce(8) || ntime(8) || root
struct StratumJob {
    let id: String
    let prevhash: Data
    let coinb1: Data
    let coinb2: Data
    let ntimeHex: String
    let ntime: Data
    let target: UInt256
    let clean: Bool

    init(params p: [Any]) throws {
        func fail(_ why: String) -> MinerError {
            .protocolError("Unsupported mining.notify (\(why)). Is this a BLAKE2b header-v2 (DATUM-style) Stratum server?")
        }
        guard p.count >= 9 else { throw fail("\(p.count) fields") }
        guard let id = p[0] as? String else { throw fail("job id") }
        guard let prev = (p[1] as? String).flatMap({ try? Data(hex: $0) }), prev.count == 32 else { throw fail("prevhash") }
        guard let cb1 = (p[2] as? String).flatMap({ try? Data(hex: $0) }),
              let cb2 = (p[3] as? String).flatMap({ try? Data(hex: $0) }) else { throw fail("coinbase parts") }
        guard let branch = p[4] as? [Any], branch.isEmpty else { throw fail("non-empty merkle branch") }
        guard let bits = (p[6] as? String).flatMap({ UInt32($0, radix: 16) }), let target = UInt256(compact: bits), !target.isZero else {
            throw fail("nbits")
        }
        guard let ntimeHex = p[7] as? String, let ntime = try? Data(hex: ntimeHex), ntime.count == 8 else {
            throw fail("ntime is not 8 bytes")
        }
        self.id = id
        prevhash = prev
        coinb1 = cb1
        coinb2 = cb2
        self.ntimeHex = ntimeHex
        self.ntime = ntime
        self.target = target
        clean = p[8] as? Bool ?? false
    }

    /// The 80-byte hasher input for a given extranonce; bytes 32..39 are the nonce.
    func input(extranonce1: Data, extranonce2: Data) -> Data {
        let root = Hash.blake2b256(Data([0]) + coinb1 + extranonce1 + extranonce2 + coinb2)
        return prevhash + Data(count: 8) + ntime + root
    }
}

func stratumErrorText(_ error: Any?) -> String? {
    guard let e = error, !(e is NSNull) else { return nil }
    if let a = e as? [Any], a.count > 1 { return "\(a[1])" }
    if let d = e as? [String: Any], let m = d["message"] { return "\(m)" }
    return "\(e)"
}

func parseSubscribe(_ result: Any?) -> (extranonce1: Data, extranonce2Size: Int)? {
    guard let r = result as? [Any], r.count >= 3, let en1 = (r[1] as? String).flatMap({ try? Data(hex: $0) }),
          let size = (r[2] as? NSNumber)?.intValue, (1...16).contains(size) else { return nil }
    return (en1, size)
}
