import Foundation

/// Mines Stratum work from a DATUM Gateway or a pool's public DATUM gateway.
/// See `StratumJob` for the work format and docs/DATUM.md for details.
final class StratumSource: WorkSource {
    private struct Job {
        let stratumID: String
        let extranonce2: Data
        let ntimeHex: String
    }

    let config: StratumConfig
    weak var miner: Miner?

    private var connection: StratumConnection?
    private var retryAt = Date.distantPast
    private var retryDelay: TimeInterval = 2
    private var subscribed = false

    private var extranonce1 = Data()
    private var extranonce2Size = 8
    private var extranonce2Counter: UInt64 = 0
    private var jobs: [UInt64: Job] = [:]
    private var nextJobID: UInt64 = 1
    private var nextRequestID = 10
    private var pendingSubmits = Set<Int>()

    private static let maxPendingSubmits = 1000

    init(config: StratumConfig) { self.config = config }

    var serverDescription: String { "Stratum \(config.url)" }

    func start() throws {
        _ = try config.endpoint()
        guard !config.user.isEmpty else {
            throw MinerError.config("Set a Stratum username (for pools, your payout address).")
        }
    }

    private func connect() throws {
        let endpoint = try config.endpoint()
        miner?.log("Connecting to \(endpoint.tls ? "TLS " : "")Stratum server \(endpoint.host):\(endpoint.port)...")
        miner?.setWaiting("Connecting to \(endpoint.host):\(endpoint.port)")
        subscribed = false
        let c = StratumConnection(endpoint)
        connection = c
        c.start(user: config.user, password: config.password)
    }

    func tick() throws {
        if connection == nil || connection!.isClosed {
            if let c = connection, case .closed(let reason) = c.state {
                connection = nil
                jobs.removeAll()
                Engine.clearWork()
                miner?.log("Stratum \(reason ?? "disconnected"); reconnecting in \(Int(retryDelay))s")
                retryAt = Date().addingTimeInterval(retryDelay)
                retryDelay = min(max(retryDelay * 2, 2), 60)
            }
            if Date() >= retryAt {
                try connect()
            } else {
                miner?.setWaiting("Can't reach the Stratum server at \(config.url); retrying")
            }
            return
        }
        for m in connection!.drain() { handle(m) }
    }

    private func handle(_ m: [String: Any]) {
        let params = m["params"] as? [Any] ?? []
        switch m["method"] as? String {
        case "mining.set_difficulty":
            let d = (params.first as? NSNumber)?.doubleValue
            miner?.updateStatus { $0.shareDifficulty = d }
        case "mining.notify":
            notify(params)
        case "client.reconnect":
            miner?.log("Server asked us to reconnect")
            connection?.close("reconnect requested by server")
            retryDelay = 0
        case nil:
            response(id: (m["id"] as? NSNumber)?.intValue, result: m["result"], error: m["error"])
        default:
            break
        }
    }

    private func response(id: Int?, result: Any?, error: Any?) {
        let errorText = stratumErrorText(error)
        switch id {
        case 1:
            guard let (en1, size) = parseSubscribe(result) else {
                connection?.close("subscribe failed: \(errorText ?? "unexpected reply")")
                return
            }
            extranonce1 = en1
            extranonce2Size = size
            subscribed = true
            retryDelay = 2
            miner?.log("Subscribed (extranonce1 \(en1.hex), extranonce2 \(size) bytes)")
        case 2:
            if result as? Bool == true {
                miner?.log("Authorized as \(config.user)")
            } else {
                miner?.log("Authorization failed for \(config.user): \(errorText ?? "rejected"). Pools usually expect a valid payout address as the username.")
            }
        case let some? where pendingSubmits.remove(some) != nil:
            if result as? Bool == true {
                miner?.updateStatus { $0.sharesAccepted += 1 }
                miner?.log("Share accepted")
            } else {
                miner?.updateStatus { $0.sharesRejected += 1 }
                miner?.log("Share rejected: \(errorText ?? "no reason given")")
            }
        default:
            break
        }
    }

    private func notify(_ params: [Any]) {
        guard subscribed else { return }
        let job: StratumJob
        do { job = try StratumJob(params: params) } catch {
            miner?.log(error.localizedDescription)
            return
        }
        // A fresh extranonce2 per job: the counter, little-endian, sized as the server asked.
        extranonce2Counter &+= 1
        var counter = Data()
        counter.appendLE(extranonce2Counter)
        let en2 = counter.prefix(extranonce2Size) + Data(count: max(0, extranonce2Size - counter.count))

        let id = nextJobID
        nextJobID += 1
        if job.clean { jobs.removeAll() }
        jobs[id] = Job(stratumID: job.id, extranonce2: en2, ntimeHex: job.ntimeHex)
        if jobs.count > 16, let oldest = jobs.keys.min() { jobs.removeValue(forKey: oldest) }
        Engine.setWork(jobID: id, input: job.input(extranonce1: extranonce1, extranonce2: en2), target: job.target)
        miner?.setMining()
    }

    func submit(jobID: UInt64, nonce8: Data) {
        guard let job = jobs[jobID], let c = connection else { return }
        let id = nextRequestID
        nextRequestID += 1
        // A server that never answers must not make this grow without bound.
        if pendingSubmits.count >= Self.maxPendingSubmits { pendingSubmits.removeAll() }
        pendingSubmits.insert(id)
        c.send(["id": id, "method": "mining.submit",
                "params": [config.user, job.stratumID, job.extranonce2.hex, job.ntimeHex, nonce8.hex]])
    }

    func stop() { connection?.close(nil) }
}
