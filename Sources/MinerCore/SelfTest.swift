import Foundation

/// Built-in verification, runnable by anyone (`b2bminer selftest` or the app's Settings).
public enum SelfTest {
    public struct Result {
        public var name: String
        public var passed: Bool
        public var detail: String
    }

    /// Runs all checks. `node` adds a check against real headers from a running node.
    public static func run(node: NodeConfig? = nil, progress: (Result) -> Void = { _ in }) -> [Result] {
        var results = [Result]()
        func record(_ name: String, _ body: () throws -> String) {
            let r: Result
            do { r = Result(name: name, passed: true, detail: try body()) } catch {
                r = Result(name: name, passed: false, detail: error.localizedDescription)
            }
            results.append(r)
            progress(r)
        }
        record("BLAKE2b known answer", knownAnswer)
        record("Knots header-v2 test vectors", vectors)
        record("Optimized engine vs reference", engineMatchesReference)
        record("Engine solutions verify", engineSolutions)
        if let node = node {
            record("Recent blocks from your node", { try nodeHeaders(node) })
        }
        return results
    }

    struct Failure: LocalizedError {
        let errorDescription: String?
        init(_ m: String) { errorDescription = m }
    }

    static func knownAnswer() throws -> String {
        let got = Hash.blake2b256(Data("abc".utf8)).hex
        guard got == "bddd813c634239723171ef3fee98579b94964e3bb1cb3e427262c8c068d52319" else { throw Failure("BLAKE2b-256(\"abc\") = \(got)") }
        return "BLAKE2b-256 matches RFC 7693"
    }

    static func vectors() throws -> String {
        guard let list = try JSONSerialization.jsonObject(with: Data(headerV2TestVectors.utf8)) as? [[String: Any]] else {
            throw Failure("could not parse embedded vectors")
        }
        for v in list {
            let f = v["fields"] as! [String: Any]
            func n(_ k: String) -> UInt64 { (f[k] as! NSNumber).uint64Value }
            func h(_ k: String) throws -> Data { try Data(hex: f[k] as! String).reversedData }
            var hd = HeaderV2(version: UInt32(n("nVersion")), prev: try h("hashPrevBlock"), merkle: try h("hashMerkleRoot"),
                              time: UInt32(n("nTime")), bits: UInt32(n("nBits")))
            hd.nonce = UInt32(n("nNonce")); hd.nonce2 = UInt32(n("m_nonce2")); hd.nonce3 = UInt32(n("m_nonce3"))
            hd.extranonce = try h("m_extranonce"); hd.timeOffset = UInt32(n("m_time_offset"))
            hd.txCount = UInt16(n("m_txcount")); hd.flags = UInt8(n("m_flags"))
            hd.xorClearBits = UInt8(n("m_xor_key_mask_clear_bits")); hd.xorKey = try h("m_xor_key")
            hd.height = Int32(n("m_height")); hd.mmRHS = try h("m_mm_rhs")
            let name = v["name"] as! String
            guard hd.serialize().hex == v["serialized"] as! String else { throw Failure("\(name): serialization differs") }
            guard hd.asicInput().hex == v["asic_input"] as! String else { throw Failure("\(name): hasher input differs") }
            guard hd.hashHex == v["block_hash"] as! String else { throw Failure("\(name): block hash differs") }
            guard try HeaderV2(serialized: hd.serialize()) == hd else { throw Failure("\(name): parse round trip differs") }
        }
        return "all \(list.count) official vectors match"
    }

    static func engineMatchesReference() throws -> String {
        var rng = SystemRandomNumberGenerator()
        for _ in 0..<5000 {
            let input = Data((0..<80).map { _ in UInt8.random(in: 0...255, using: &rng) })
            guard Engine.hash80(input) == Hash.blake2b256(input) else { throw Failure("hash mismatch on input \(input.hex)") }
        }
        return "5,000 random inputs match"
    }

    static func engineSolutions() throws -> String {
        guard Engine.threads == 0 else { return "skipped while mining" }
        var hd = HeaderV2(version: 0x2000_0000, prev: Data((0..<32).map { _ in .random(in: 0...255) }),
                          merkle: Data((0..<32).map { _ in .random(in: 0...255) }), time: 1_790_000_000, bits: 0x1f00ffff)
        hd.height = 975_300
        hd.txCount = 5
        let easy = UInt256(words: [0x0000_0fff_ffff_ffff, .max, .max, .max])
        try Engine.start(threads: 2, lowPriority: false)
        defer { Engine.stop() }
        Engine.setWork(jobID: 7, input: hd.asicInput(), target: easy)
        Thread.sleep(forTimeInterval: 0.5)
        var count = 0
        while let (job, nonce) = Engine.takeSolution() {
            hd.nonce = nonce.readLE(UInt32.self, at: 0)
            hd.nonce2 = nonce.readLE(UInt32.self, at: 4)
            guard job == 7, UInt256(littleEndian: hd.hash) <= easy else { throw Failure("engine reported an invalid solution") }
            count += 1
        }
        guard count > 0 else { throw Failure("no solutions found for an easy target") }
        return "\(count) solutions, all valid"
    }

    static func nodeHeaders(_ node: NodeConfig) throws -> String {
        let rpc = NodeRPC(node, timeout: 15)
        guard let tip = try rpc.call("getblockcount") as? Int else { throw Failure("no block count") }
        var checked = 0
        for height in stride(from: tip, to: max(tip - 50, 0), by: -1) {
            guard let hash = try rpc.call("getblockhash", [height]) as? String,
                  let raw = try rpc.call("getblockheader", [hash, false]) as? String else { continue }
            let data = try Data(hex: raw)
            guard data.count == HeaderV2.serializedSize else { break }  // reached pre-fork SHA256d blocks
            let h = try HeaderV2(serialized: data)
            guard h.hashHex == hash, h.meetsTarget else { throw Failure("block \(height): computed \(h.hashHex), node says \(hash)") }
            checked += 1
        }
        guard checked > 0 else { throw Failure("the node has no BLAKE2b blocks to compare against") }
        return "reproduced the hashes of the last \(checked) blocks"
    }
}
