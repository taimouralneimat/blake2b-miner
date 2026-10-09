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
        record("GPU kernel vs reference", gpuMatchesReference)
        record("DATUM Gateway output handling", gatewayOutput)
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

    /// One entry of Knots' src/test/data/block_header_v2.json.
    private struct Vector: Decodable {
        struct Fields: Decodable {
            let nVersion: UInt32, nTime: UInt32, nBits: UInt32, nNonce: UInt32
            let m_nonce2: UInt32, m_nonce3: UInt32, m_time_offset: UInt32, m_txcount: UInt16
            let m_flags: UInt8, m_xor_key_mask_clear_bits: UInt8, m_height: Int32
            let hashPrevBlock: String, hashMerkleRoot: String, m_extranonce: String, m_xor_key: String, m_mm_rhs: String
        }
        let name: String
        let fields: Fields
        let serialized: String
        let asic_input: String
        let block_hash: String
    }

    static func vectors() throws -> String {
        let list = try JSONDecoder().decode([Vector].self, from: Data(headerV2TestVectors.utf8))
        // Hashes and 128-bit fields are given in display order (byte-reversed).
        func displayOrder(_ hex: String) throws -> Data { try Data(hex: hex).reversedData }
        for v in list {
            let f = v.fields
            var hd = HeaderV2(version: f.nVersion, prev: try displayOrder(f.hashPrevBlock), merkle: try displayOrder(f.hashMerkleRoot),
                              time: f.nTime, bits: f.nBits)
            hd.nonce = f.nNonce; hd.nonce2 = f.m_nonce2; hd.nonce3 = f.m_nonce3
            hd.extranonce = try displayOrder(f.m_extranonce); hd.timeOffset = f.m_time_offset
            hd.txCount = f.m_txcount; hd.flags = f.m_flags
            hd.xorClearBits = f.m_xor_key_mask_clear_bits; hd.xorKey = try displayOrder(f.m_xor_key)
            hd.height = f.m_height; hd.mmRHS = try displayOrder(f.m_mm_rhs)
            guard hd.serialize().hex == v.serialized else { throw Failure("\(v.name): serialization differs") }
            guard hd.asicInput().hex == v.asic_input else { throw Failure("\(v.name): hasher input differs") }
            guard hd.hashHex == v.block_hash else { throw Failure("\(v.name): block hash differs") }
            guard try HeaderV2(serialized: hd.serialize()) == hd else { throw Failure("\(v.name): parse round trip differs") }
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

    /// The GPU kernel's first output word for 2,048 nonces against the reference hash.
    static func gpuMatchesReference() throws -> String {
        var input = Data((0..<80).map { _ in UInt8.random(in: 0...255) })
        let base = GPUEngine.firstNonce + 12_345
        guard let (gpu, words) = Engine.gpuDebugWords(input: input, base: base, threads: 128) else {
            return "no Metal GPU on this Mac (CPU mining only)"
        }
        guard let words = words else { throw Failure("the GPU didn't run the kernel") }
        for (i, word) in words.enumerated() {
            let nonce = base + UInt64(i)
            withUnsafeBytes(of: nonce.littleEndian) { input.replaceSubrange(32..<40, with: $0) }
            guard word == Hash.blake2b256(input).readLE(UInt64.self, at: 0) else {
                throw Failure("GPU hash mismatch at nonce \(String(nonce, radix: 16))")
            }
        }
        return "\(gpu): \(words.count.formatted()) nonces match"
    }

    static func engineSolutions() throws -> String {
        try Engine.withSelfTestEngine(threads: 2) { try findEasySolutions() } ?? "skipped while mining"
    }

    private static func findEasySolutions() throws -> String {
        var hd = HeaderV2(version: 0x2000_0000, prev: Data((0..<32).map { _ in .random(in: 0...255) }),
                          merkle: Data((0..<32).map { _ in .random(in: 0...255) }), time: 1_790_000_000, bits: 0x1f00ffff)
        hd.height = 975_300
        hd.txCount = 5
        // About one hash in 65,536 meets this target, so solutions arrive within
        // milliseconds natively and well within the time limit under emulation.
        let easy = UInt256(words: [0x0000_ffff_ffff_ffff, .max, .max, .max])
        Engine.setWork(jobID: 7, input: hd.asicInput(), target: easy)
        var count = 0
        let deadline = Date().addingTimeInterval(10)
        while count < 3 && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
            while let (job, nonce) = Engine.takeSolution() {
                hd.nonce = nonce.readLE(UInt32.self, at: 0)
                hd.nonce2 = nonce.readLE(UInt32.self, at: 4)
                guard job == 7, UInt256(littleEndian: hd.hash) <= easy else { throw Failure("engine reported an invalid solution") }
                count += 1
            }
        }
        guard count > 0 else { throw Failure("no solutions found for an easy target within 10 seconds") }
        return "\(count) solutions, all valid"
    }

    /// Feeds real DATUM Gateway output lines to the parser that turns them into
    /// found blocks, alerts and pool/node state.
    static func gatewayOutput() throws -> String {
        var p = GatewayOutputParser(poolName: "DXPool", nodeAddress: "127.0.0.1:8332")
        let t0 = Date()
        let hashA = String(repeating: "a1", count: 32), hashB = String(repeating: "b2", count: 32)
        func feed(_ line: String, _ seconds: TimeInterval = 0) -> [String] { p.consume(line, at: t0.addingTimeInterval(seconds)) }

        guard p.poolState == .connecting else { throw Failure("initial pool state") }
        _ = feed("2026-10-03 19:04:26.377 [datum_protocol_handshake_response]  INFO: DATUM Server MOTD: RATUM Prime")
        guard p.poolState == .connected("DXPool") else { throw Failure("handshake not recognized") }

        // Banner lines are dropped; both ways of announcing a block are recognized.
        guard feed("2026-10-03 18:46:42.100  WARN: ************************************************").isEmpty else {
            throw Failure("banner line was not dropped")
        }
        _ = feed("2026-10-03 18:46:42.101  WARN: ******** BLOCK FOUND - \(hashA) ********")
        _ = feed("2026-10-03 18:46:42.200  WARN: DATUM server revealed a verified block key for candidate \(hashB)")
        guard p.takeFoundHashes() == [hashA, hashB], p.takeFoundHashes().isEmpty else { throw Failure("found blocks") }

        // The pool ignoring a block is reported once, not 8 times.
        let alerts = (0..<8).flatMap { _ in feed("ERROR: CRITICAL ABW FAILURE: pool ignored valid block \(hashB)") }
        guard alerts.count == 1, alerts[0].contains("ALERT") else { throw Failure("ABW failure alert: \(alerts.count) messages") }

        // Network blocks are one short line, not three.
        let tip = feed("INFO: NEW NETWORK BLOCK NOTIFICATION RECEIVED")
            + feed("INFO: NEW NETWORK BLOCK: \(hashA) (975723)")
            + feed("INFO: NEW NETWORK BLOCK NOTIFICATION RECEIVED")
        guard tip == ["[gateway] New network block 975723"] else { throw Failure("network block lines: \(tip)") }

        // A node outage is reported once, then its recovery once.
        let outage = (0..<5).flatMap { feed("ERROR: Could not fetch new template from http://127.0.0.1:8332!", Double($0)) }
        guard outage.count == 1, p.templatesFailingSince != nil else { throw Failure("outage reported \(outage.count) times") }
        let back = feed("INFO: Updating standard stratum job for block 975350: 3.13 BTC, 213 txns, 90000 bytes", 20)
        guard back.count == 1, back[0].contains("again (after 20 s)"), p.templatesFailingSince == nil else {
            throw Failure("outage recovery")
        }

        // A Stratum port taken by another program is recognized.
        guard !p.portInUse else { throw Failure("port in use before any bind failure") }
        _ = feed("2026-10-09 09:18:44.100 [datum_stratum_v1_socket_server] FATAL: bind failed (stratum): Address already in use")
        guard p.portInUse else { throw Failure("port in use not recognized") }

        // Three resets within two minutes is a reconnect loop; spread out, it is not.
        for second in [100.0, 130, 160] { _ = feed("ERROR: Socket error: Connection reset by peer", second) }
        guard p.poolConnectionLooping(at: t0.addingTimeInterval(170)) else { throw Failure("reconnect loop not detected") }
        guard !p.poolConnectionLooping(at: t0.addingTimeInterval(400)) else { throw Failure("old resets still counted") }
        return "blocks, alerts, outages, busy ports and reconnect loops recognized"
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
