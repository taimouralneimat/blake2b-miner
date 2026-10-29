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
        record("Stratum share targets", stratumTargets)
        record("Address checksums", addressChecksums)
        record("Responsive schedule", responsiveSchedule)
        record("Local network", localNetwork)
        record("Node version rule", nodeVersionRule)
        record("Retired pools", retiredPools)
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

    /// Pool difficulty to share target, against the compact targets pools send as nbits:
    /// exact where the division is exact, within rounding for a pool's rounded difficulty.
    static func stratumTargets() throws -> String {
        for (difficulty, bits) in [(1.0, UInt32(0x1d00ffff)), (256, 0x1c00ffff)] {
            guard UInt256(difficulty: difficulty) == UInt256(compact: bits) else {
                throw Failure("difficulty \(difficulty) does not give target \(String(bits, radix: 16))")
            }
        }
        // DXPool's gateway: nbits 1b03ffff, announced as difficulty 16,383.75.
        guard let target = UInt256(difficulty: 16383.75), let pool = UInt256(compact: 0x1b03ffff),
              abs(target.doubleValue / pool.doubleValue - 1) < 1e-5 else { throw Failure("difficulty 16,383.75") }
        guard UInt256(difficulty: 0) == nil, UInt256(difficulty: 1e-12) != nil else { throw Failure("edge cases") }
        return "difficulty 1 and 256 exact, a pool's 16,383.75 within rounding"
    }

    /// Knots older than 29.4.2 doesn't know the 45-day coinbase maturity rule.
    static func nodeVersionRule() throws -> String {
        let outdated = ["/Satoshi:29.4.1/Knots:20260508/", "/Satoshi:29.4/Knots:20260508/", "/Satoshi:28.1.0/Knots:20250305/"]
        let current = ["/Satoshi:29.4.2/Knots:20260508/", "/Satoshi:29.5.0/Knots:20261101/", "/Satoshi:30.0/Knots:20270101/"]
        for v in outdated where NodeCheck.outdatedNode(v) == nil { throw Failure("\(v) not flagged as outdated") }
        for v in current where NodeCheck.outdatedNode(v) != nil { throw Failure("\(v) flagged as outdated") }
        return "Knots before 29.4.2 is flagged, 29.4.2 and later pass"
    }

    /// A retired pool leaves your saved pools unless you're mining with it; then it stays, with its note.
    static func retiredPools() throws -> String {
        guard let rabid = DatumPool.retired.first(where: { $0.id == "rabid" }) else { throw Failure("Rabid isn't retired") }
        var bare = rabid
        bare.note = nil
        var mine = rabid
        mine.id = "my-pool"
        func load(_ poolID: String) throws -> GatewaySettings {
            let pools = String(decoding: try JSONEncoder().encode([bare, mine]), as: UTF8.self)
            return try JSONDecoder().decode(GatewaySettings.self, from: Data(#"{"poolID":"\#(poolID)","customPools":\#(pools)}"#.utf8))
        }
        let other = try load("lazarus")
        guard other.customPools.map(\.id) == ["my-pool"] else { throw Failure("kept \(other.customPools.map(\.id)) while mining with Lazarus") }
        let chosen = try load("rabid")
        guard let kept = chosen.customPools.first(where: { $0.id == "rabid" }) else { throw Failure("dropped the pool you mine with") }
        guard kept.note == rabid.note else { throw Failure("the pool you mine with lost its note") }
        // Saved data that names a statistics API no longer in the app still loads.
        let oldPool = #"{"id":"omega","name":"Omega Pool","host":"omegapool.tech","port":28915,"pubkey":"00","fee":"0.5%","website":"https://omegapool.tech","statsAPI":"omega"}"#
        let pool = try JSONDecoder().decode(DatumPool.self, from: Data(oldPool.utf8))
        guard pool.statsAPI == nil else { throw Failure("an unknown statistics API wasn't dropped") }
        let apis = try JSONDecoder().decode([Lossy<PoolStatsAPI>].self, from: Data(#"["lazarus","omega","b2pool"]"#.utf8)).compactMap(\.value)
        guard apis == [.lazarus, .b2pool] else { throw Failure("lossy decoding kept \(apis)") }
        return "dropped unless chosen; a chosen one keeps working with its note; old saved pools still load"
    }

    /// Keep-responsive hours: inside and outside them, weekends, and hours past midnight.
    static func responsiveSchedule() throws -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {  // October 2026; the 19th is a Monday
            cal.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
        }
        var s = ResponsiveSchedule()  // 9:00–17:00, Monday to Friday
        s.enabled = true
        let checks: [(Date, Bool)] = [(at(19, 9), true), (at(19, 16, 59), true), (at(19, 17), false), (at(19, 8, 59), false),
                                      (at(24, 12), false)]  // Saturday
        for (date, expected) in checks where s.isActive(at: date, calendar: cal) != expected {
            throw Failure("9–17 weekdays at \(date): expected \(expected)")
        }
        s.start = 22 * 60; s.end = 6 * 60  // overnight, Friday night counts as a weekday night
        let night: [(Date, Bool)] = [(at(23, 23), true), (at(24, 3), true), (at(24, 23), false), (at(19, 12), false)]
        for (date, expected) in night where s.isActive(at: date, calendar: cal) != expected {
            throw Failure("22–6 weekdays at \(date): expected \(expected)")
        }
        s.start = 9 * 60; s.end = 17 * 60; s.days = [1, 7]  // weekends only
        guard s.isActive(at: at(24, 12), calendar: cal), !s.isActive(at: at(23, 12), calendar: cal) else {
            throw Failure("chosen days")
        }
        // In words: Sun–Thu (a Gulf work week), 9:00–midnight, on a Saturday afternoon.
        s.start = 9 * 60; s.end = 0; s.days = [1, 2, 3, 4, 5]
        guard s.summary == "9:00–midnight, Sun–Thu",
              s.explanation(at: at(24, 16, 42), calendar: cal) == "Full power: Saturday isn't one of your days (Sun–Thu)",
              s.isActive(at: at(25, 16, 42), calendar: cal) else { throw Failure("summary: \(s.summary)") }
        s.days = [6, 7, 1]
        guard s.daysSummary == "Fri–Sun" else { throw Failure("days across the weekend: \(s.daysSummary)") }
        s.enabled = false
        guard !s.isActive(at: at(19, 23), calendar: cal) else { throw Failure("a schedule that is off") }
        return "daytime, overnight and chosen-day hours"
    }

    /// Which gateway addresses count as your own network (for "who builds the blocks").
    static func localNetwork() throws -> String {
        let local = ["127.0.0.1", "localhost", "192.168.1.20", "10.0.0.5", "172.20.1.1", "mac-mini.local", "169.254.3.4"]
        let remote = ["de.b2pool.io", "8.8.8.8", "172.32.0.1", "192.169.1.1", "pool.example.com"]
        for h in local where !LocalNetwork.isLocal(h) { throw Failure("\(h) should be local") }
        for h in remote where LocalNetwork.isLocal(h) { throw Failure("\(h) should not be local") }
        return "\(local.count) local and \(remote.count) outside addresses told apart"
    }

    /// BIP173/BIP350 and base58check vectors, and mistyped versions of them.
    static func addressChecksums() throws -> String {
        let valid = ["BC1QW508D6QEJXTDG4Y5R3ZARVARY0C5XW7KV8F3T4", "bc1qrp33g0q5c5txsp9arysrx4k6zdkfs4nce4xj0gdcccefvpysxf3qccfmv3",
                     "bc1pw508d6qejxtdg4y5r3zarvary0c5xw7kw508d6qejxtdg4y5r3zarvary0c5xw7kt5nd6y",
                     "tb1qqqqqp399et2xygdj5xreqhjjvcmzhxw4aywxecjdzew6hylgvsesrxh6hy", "1BvBMSEYstWetqTFn5Au4m4GFg7xJaNVN2",
                     "3J98t1WpEZ73CNmQviecrnyiWrnqRhWNLy", "1PQCmfrWbL2FYv76Wp5rx45FBuLXGegBMj", "bc1zw508d6qejxtdg4y5r3zarvaryvaxxpcs"]
        let invalid = ["bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t5",  // last character changed
                       "bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kemeawh",  // version 0 with a bech32m checksum
                       "bc1p0xlxvlhemja6c4dqv22uapctqupfhlxm9h8z3k2e72q4k9hcz7vqh2y7hd",  // version 1 with bech32
                       "1BvBMSEYstWetqTFn5Au4m4GFg7xJaNVN3", "3J98t1WpEZ73CNmQviecrnyiWrnqRhWNLz"]
        for a in valid where AddressFormat.check(a) != .valid { throw Failure("\(a) rejected: \(AddressFormat.check(a))") }
        for a in invalid where AddressFormat.check(a) == .valid { throw Failure("\(a) accepted") }
        return "\(valid.count) valid and \(invalid.count) mistyped addresses told apart"
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
        var p = GatewayOutputParser(poolName: "Lazarus", nodeAddress: "127.0.0.1:8332")
        let t0 = Date()
        let hashA = String(repeating: "a1", count: 32), hashB = String(repeating: "b2", count: 32)
        func feed(_ line: String, _ seconds: TimeInterval = 0) -> [String] { p.consume(line, at: t0.addingTimeInterval(seconds)) }

        guard p.poolState == .connecting else { throw Failure("initial pool state") }
        _ = feed("2026-10-03 19:04:26.377 [datum_protocol_handshake_response]  INFO: DATUM Server MOTD: RATUM Prime")
        guard p.poolState == .connected("Lazarus") else { throw Failure("handshake not recognized") }

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

        // The pool's verdicts on forwarded shares (debug-level lines) are counted, with
        // the rejection reason in words; other debug lines are ignored.
        let accepted = feed("2026-10-10 05:00:00.100  DEBUG: Share accepted: NONCE: 1a2b3c4d / TargetPOT: 0a / Job ID: 3")
        let rejected = feed("2026-10-10 05:00:01.100  DEBUG: DATUM server rejected our share!  Reason code: 21 / TargetPOT: 0a / Job ID: 3 / Nonce: 1a2b3c4d")
        let ignored = feed("2026-10-10 05:00:02.100  DEBUG: some routine detail ERROR WARN")
        guard p.poolAccepted == 1, p.poolRejected == 1, accepted == ["[gateway] Lazarus accepted your share"],
              rejected.first?.contains("rejected your share") == true, p.lastRejectReason?.contains("code 21") == true,
              ignored.isEmpty, !p.recentLines.contains(where: { $0.hasPrefix("DEBUG:") }) else {
            throw Failure("pool share verdicts")
        }

        // A Stratum port taken by another program is recognized.
        guard !p.portInUse else { throw Failure("port in use before any bind failure") }
        _ = feed("2026-10-09 09:18:44.100 [datum_stratum_v1_socket_server] FATAL: bind failed (stratum): Address already in use")
        guard p.portInUse else { throw Failure("port in use not recognized") }

        // Three resets within two minutes is a reconnect loop; spread out, it is not.
        for second in [100.0, 130, 160] { _ = feed("ERROR: Socket error: Connection reset by peer", second) }
        guard p.poolConnectionLooping(at: t0.addingTimeInterval(170)) else { throw Failure("reconnect loop not detected") }
        guard !p.poolConnectionLooping(at: t0.addingTimeInterval(400)) else { throw Failure("old resets still counted") }

        // A reset means the pool is disconnected (shares mined now are solo work);
        // a declined resume drops the queued shares; a restarted gateway keeps the
        // session's verdicts.
        guard case .problem = p.poolState else { throw Failure("connection reset not seen as disconnected") }
        _ = feed("INFO: DATUM Server MOTD: Proverbs 11:1")
        _ = feed("WARN: DATUM resume was declined; discarded queued shares from the old session")
        let next = p.continued()
        guard p.queueDiscards == 1, next.poolAccepted == 1, next.poolRejected == 1, next.queueDiscards == 1,
              next.poolState == .connecting else { throw Failure("verdicts across a gateway restart") }
        // A session whose shares are all rejected is stuck; a reconnect clears it.
        var s = GatewayOutputParser(poolName: "RIPTIDE", nodeAddress: "127.0.0.1:8332")
        _ = s.consume("INFO: DATUM Server MOTD: TIDES lab DATUM Prime")
        for _ in 0..<3 { _ = s.consume("DEBUG: DATUM server rejected our share!  Reason code: 30 / TargetPOT: 0b / Job ID: 1 / Nonce: 1") }
        guard s.poolSessionStuck else { throw Failure("stuck pool session not detected") }
        _ = s.consume("INFO: DATUM Server MOTD: TIDES lab DATUM Prime")
        guard !s.poolSessionStuck, s.poolRejected == 3 else { throw Failure("a new pool session should start clean") }
        guard GatewayOutputParser.rejectReason(43).contains("payout outputs"),
              GatewayOutputParser.rejectReason(45) == "reason unknown" else { throw Failure("RATUM reject codes") }
        guard formatAmount(0.00001108) == "1,108 sats", formatAmount(0.00000001) == "1 sat",
              formatAmount(3.125) == "3.125 BTC" else { throw Failure("amounts: \(formatAmount(0.00001108))") }
        return "blocks, alerts, outages, pool verdicts across restarts, disconnects, busy ports and reconnect loops recognized"
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
