import Foundation

/// Solo mining straight from a local Bitcoin Knots node via getblocktemplate.
final class SoloSource: WorkSource {
    struct Job {
        let id: UInt64
        let prev: String
        let height: Int
        var header: HeaderV2
        let target: UInt256
        let coinbase: Data
        let transactions: [Data]
        let reward: Double

        var blockHex: String {
            var body = Data()
            body += varint(1 + transactions.count)
            body += coinbase
            for tx in transactions { body += tx }
            return (header.serialize() + body).hex
        }
    }

    static let rules = ["segwit", "blake2b"]

    let rpc: NodeRPC
    let address: String
    let coinbaseTag: Data
    let templateRefresh: TimeInterval = 30
    weak var miner: Miner?

    private var payoutScript = Data()
    private var jobs: [UInt64: Job] = [:]
    private var current: Job?
    private var nextJobID: UInt64 = 1
    private var lastTemplate = Date.distantPast

    init(node: NodeConfig, address: String, coinbaseTag: String) {
        rpc = NodeRPC(node)
        self.address = address.trimmingCharacters(in: .whitespaces)
        self.coinbaseTag = Data(coinbaseTag.utf8.prefix(40))
    }

    var serverDescription: String { "Knots node \(rpc.config.host):\(rpc.config.port)" }

    func start() throws {
        let info = try rpc.call("getblockchaininfo") as? [String: Any] ?? [:]
        if info["initialblockdownload"] as? Bool == true {
            throw MinerError.config("The node is still syncing the blockchain; mining now would waste work.")
        }
        guard !address.isEmpty else { throw MinerError.config("Set a payout address first.") }
        let v = try rpc.call("validateaddress", [address]) as? [String: Any] ?? [:]
        guard v["isvalid"] as? Bool == true, let script = v["scriptPubKey"] as? String else {
            throw MinerError.config("\(address) is not a valid address for this node's chain (\(info["chain"] ?? "?")).")
        }
        payoutScript = try Data(hex: script)
        miner?.log("Connected to node: chain \(info["chain"] ?? "?"), height \(info["blocks"] ?? "?"). Payout: \(address)")
    }

    func tick() throws {
        let tip = try rpc.call("getbestblockhash") as? String ?? ""
        let newTip = current?.prev != tip
        guard newTip || Date().timeIntervalSince(lastTemplate) >= templateRefresh else { return }
        guard let job = try makeJob() else { return }  // tip moved meanwhile; next tick retries
        lastTemplate = Date()
        jobs = jobs.filter { $0.value.prev == job.prev }
        jobs[job.id] = job
        current = job
        Engine.setWork(jobID: job.id, input: job.header.asicInput(), target: job.target)
        miner?.setMining()
        miner?.updateStatus {
            $0.height = job.height
            $0.networkDifficulty = difficulty(bits: job.header.bits)
            $0.transactions = job.transactions.count
            $0.reward = job.reward
        }
        if newTip {
            miner?.log(String(format: "New block to mine: height %d, %d transactions, reward %.8f, difficulty %@",
                              job.height, job.transactions.count, job.reward,
                              difficulty(bits: job.header.bits).formatted(.number.notation(.compactName))))
        }
    }

    private func makeJob() throws -> Job? {
        guard let t = try rpc.call("getblocktemplate", [["rules": Self.rules]]) as? [String: Any] else {
            throw MinerError.rpc("getblocktemplate returned nothing")
        }
        guard let version = (t["version"] as? NSNumber)?.uint32Value, version & HeaderV2.versionFlag != 0 else {
            throw MinerError.config("The node's block template is not a BLAKE2b (header v2) block. Is this Bitcoin Knots on the BLAKE2b chain?")
        }
        guard let prev = t["previousblockhash"] as? String, let height = t["height"] as? Int,
              let value = (t["coinbasevalue"] as? NSNumber)?.int64Value, let bitsHex = t["bits"] as? String,
              let bits = UInt32(bitsHex, radix: 16), let curtime = (t["curtime"] as? NSNumber)?.uint32Value,
              let txs = t["transactions"] as? [[String: Any]] else {
            throw MinerError.rpc("Incomplete block template")
        }
        let id = nextJobID
        nextJobID += 1

        var tag = coinbaseTag
        tag.appendLE(UInt32(truncatingIfNeeded: id))
        tag.appendLE(UInt32.random(in: 0...UInt32.max))
        let commitment = try (t["default_witness_commitment"] as? String).map { try Data(hex: $0) }
        let (coinbase, coinbaseTxid) = try buildCoinbase(height: height, value: value, script: payoutScript,
                                                         witnessCommitment: commitment, tag: tag)
        var txids = [coinbaseTxid]
        var txData = [Data]()
        for tx in txs {
            guard let txid = tx["txid"] as? String, let data = tx["data"] as? String else { throw MinerError.rpc("Bad template transaction") }
            txids.append(try Data(hex: txid).reversedData)
            txData.append(try Data(hex: data))
        }
        var header = HeaderV2(version: version, prev: try Data(hex: prev).reversedData, merkle: merkleRoot(txids),
                              time: curtime, bits: bits)
        guard let txCount = UInt16(exactly: 1 + txs.count) else {
            throw MinerError.rpc("Block template has too many transactions (\(txs.count))")
        }
        header.txCount = txCount
        header.height = Int32(height)
        guard let target = header.target else { throw MinerError.rpc("Template has an invalid target") }
        let job = Job(id: id, prev: prev, height: height, header: header, target: target, coinbase: coinbase,
                      transactions: txData, reward: Double(value) / 1e8)

        // The node validates the whole block except proof of work before we spend effort on it.
        let verdict = try rpc.call("getblocktemplate", [["mode": "proposal", "data": job.blockHex, "rules": Self.rules]])
        if let reason = verdict as? String {
            if reason == "inconclusive-not-best-prevblk" { return nil }
            throw MinerError.rpc("The node rejected the block we built (\(reason)). Please report this.")
        }
        return job
    }

    func submit(jobID: UInt64, nonce8: Data) {
        guard var job = jobs[jobID] else { return }  // stale or already solved
        job.header.nonce = nonce8.readLE(UInt32.self, at: 0)
        job.header.nonce2 = nonce8.readLE(UInt32.self, at: 4)
        guard job.header.meetsTarget else {
            miner?.log("Internal error: engine solution failed the reference check (job \(jobID)). Please report this.")
            return
        }
        let hash = job.header.hashHex
        miner?.log("BLOCK SOLVED at height \(job.height): \(hash). Submitting...")
        let hex = job.blockHex
        let result = submitBlock(hex)
        if result == FoundBlock.accepted {
            jobs = jobs.filter { $0.value.prev != job.prev }  // this height is done
            current = nil  // fetch the next template right away
        }
        miner?.log("Block \(hash) \(result)")
        miner?.recordBlock(FoundBlock(time: Date(), height: job.height, hash: hash, result: result, blockHex: hex))
    }

    /// Submits a solved block. Connection problems are retried, because the
    /// node may be restarting and a found block is worth waiting a little for.
    private func submitBlock(_ hex: String) -> String {
        var lastError = ""
        for attempt in 1...Self.submitAttempts {
            do {
                let reply = try rpc.call("submitblock", [hex])
                return reply is NSNull ? FoundBlock.accepted : "rejected: \(reply)"
            } catch MinerError.connection(let message) {
                lastError = message
                miner?.log("Submitting the block failed (attempt \(attempt) of \(Self.submitAttempts)): \(message)")
                if attempt < Self.submitAttempts { Thread.sleep(forTimeInterval: 3) }
            } catch {
                return "submit failed: \(error.localizedDescription)"
            }
        }
        return "submit failed: \(lastError). The block is saved in found-blocks.jsonl and can be submitted with `bitcoin-cli submitblock`."
    }

    private static let submitAttempts = 5

    func stop() {}
}

// MARK: - Block construction

func varint(_ n: Int) -> Data {
    var d = Data()
    switch n {
    case ..<0xfd: d.append(UInt8(n))
    case ...0xffff: d.append(0xfd); d.appendLE(UInt16(n))
    case ...0xffff_ffff: d.append(0xfe); d.appendLE(UInt32(n))
    default: d.append(0xff); d.appendLE(UInt64(n))
    }
    return d
}

/// A minimal script push for up to 75 bytes.
private func push(_ data: Data) throws -> Data {
    guard data.count < 0x4c else { throw MinerError.config("coinbase data too long (\(data.count) bytes)") }
    return Data([UInt8(data.count)]) + data
}

/// `CScript() << height` (BIP34).
func scriptNum(_ n: Int) throws -> Data {
    if (1...16).contains(n) { return Data([UInt8(0x50 + n)]) }
    var bytes = [UInt8]()
    var v = n
    while v > 0 { bytes.append(UInt8(v & 0xff)); v >>= 8 }
    if let last = bytes.last, last & 0x80 != 0 { bytes.append(0) }
    return try push(Data(bytes))
}

/// Returns the serialized coinbase (with witness when committing) and its txid (internal order).
func buildCoinbase(height: Int, value: Int64, script: Data, witnessCommitment: Data?, tag: Data) throws -> (Data, Data) {
    let scriptSig = try scriptNum(height) + push(tag)
    guard (2...100).contains(scriptSig.count) else { throw MinerError.config("coinbase scriptSig too long") }
    var txin = Data(count: 32)
    txin.appendLE(UInt32.max)
    txin += varint(scriptSig.count) + scriptSig
    txin.appendLE(UInt32.max)
    var outputs: [(Int64, Data)] = [(value, script)]
    if let c = witnessCommitment { outputs.append((0, c)) }
    var outs = varint(outputs.count)
    for (v, s) in outputs {
        outs.appendLE(v)
        outs += varint(s.count) + s
    }
    var version = Data(); version.appendLE(Int32(2))
    var locktime = Data(); locktime.appendLE(UInt32(0))
    let stripped = version + varint(1) + txin + outs + locktime
    guard witnessCommitment != nil else { return (stripped, Hash.sha256d(stripped)) }
    // Witness reserved value: one 32-byte zero item, which the node's commitment assumes.
    let full = version + Data([0x00, 0x01]) + varint(1) + txin + outs + Data([0x01, 0x20]) + Data(count: 32) + locktime
    return (full, Hash.sha256d(stripped))
}

func merkleRoot(_ txids: [Data]) -> Data {
    var layer = txids
    while layer.count > 1 {
        if layer.count % 2 == 1 { layer.append(layer.last!) }
        layer = stride(from: 0, to: layer.count, by: 2).map { Hash.sha256d(layer[$0] + layer[$0 + 1]) }
    }
    return layer[0]
}
