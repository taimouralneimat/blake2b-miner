import Foundation

/// A DATUM pool that your own gateway can connect to. With DATUM your node
/// builds the block templates; the pool only coordinates payouts.
/// Each built-in entry was verified by completing the encrypted DATUM handshake
/// with the bundled gateway; the public key authenticates the pool. You can add
/// your own pools too (`GatewaySettings.customPools`).
public struct DatumPool: Identifiable, Hashable, Codable {
    public var id: String
    public var name: String
    public var host: String
    public var port: Int
    /// The pool's DATUM public key (128 hex digits): the gateway checks the pool's
    /// handshake against it, so nobody can impersonate the pool.
    public var pubkey: String
    public var fee: String
    public var website: String
    /// The smallest share difficulty the pool accepts, when it publishes one.
    public var minDifficulty: Double?
    /// A caution shown when the pool is chosen.
    public var note: String?
    /// The pool's public API for your address's statistics, if it has one.
    public var statsAPI: PoolStatsAPI?
    /// How and from what amount the pool pays.
    public var payout: String?

    public init(id: String, name: String, host: String, port: Int, pubkey: String, fee: String, website: String,
                minDifficulty: Double? = nil, note: String? = nil, statsAPI: PoolStatsAPI? = nil, payout: String? = nil) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.pubkey = pubkey
        self.fee = fee
        self.website = website
        self.minDifficulty = minDifficulty
        self.note = note
        self.statsAPI = statsAPI
        self.payout = payout
    }

    /// The pool new installs start with, and the fallback when a chosen pool is removed:
    /// Lazarus, the built-in pool verified to credit a Mac's small amounts (it carries
    /// them until its payout minimum).
    public static let recommendedID = "lazarus"

    /// Built-in pools meet four rules: they found blocks in the last 7 days (by their
    /// coinbase tags on the chain), their DATUM server accepts shares at a low difficulty
    /// (measured through the bundled gateway), they publish live status (checked
    /// 2026-10-10), and they credit a small miner's work instead of dropping it (added
    /// 2026-10-17). Any other pool can be added as a custom pool.
    public static let all: [DatumPool] = [
        // 201 blocks in the 7 days; status API at https://pool.lazarus-xbt.xyz/api/pool.
        DatumPool(id: "lazarus", name: "Lazarus", host: "datum.lazarus-xbt.xyz", port: 28915,
                  pubkey: "29120606bbbfdeb0dcb259d13ed1fba9e6ff198ff6a0152cffb7608dc1c266bd17532393738aee7edf9aa0c9ec93b835256971f186da878f77fb3ed273dff30a",
                  fee: "0% through your own gateway", website: "https://pool.lazarus-xbt.xyz", minDifficulty: 1024,
                  statsAPI: .lazarus,
                  // min_payout_btc in its miner API (2026-10-15).
                  payout: "In a found block's coinbase once you're owed 500,000 sats (0.005 BTC); smaller amounts carry over to later blocks"),
    ]

    /// Pools being tested against the rules on a real Mac before they're built in;
    /// the Pools page lists them, and anyone can join the test (as a custom pool).
    public static let underEvaluation: [(pool: DatumPool, testing: String)] = []

    /// Pools that were built in before and no longer meet the rules. A saved choice of
    /// one is kept as a custom pool, so nothing changes silently.
    public static let retired: [DatumPool] = [
        // Trial ended 2026-10-25: no accepted share in two days at difficulty 16,384, so its
        // carried balance couldn't be checked, and its website and stats API were unreachable.
        DatumPool(id: "rabid", name: "Rabid Pool", host: "xbt.rabidmining.com", port: 28916,
                  pubkey: "9f41d02bfaf09d18d0db09711912a946ed2698c2f5507ab4f79a68655fb1f476e5127f60501b739eb6e89606bb0267f74750ebb55a75c7ef21434bf60ca66920",
                  fee: "1%", website: "https://pool.rabidmining.com/xbt", minDifficulty: 16384,
                  note: "Trial ended: Rabid's share difficulty (16,384) means about one share a day from a Mac, so in two days of testing it showed no credit, and its website and statistics were unreachable. The Pools page shows the pools that credit a Mac.",
                  statsAPI: .rabid,
                  payout: "In a found block's coinbase once you're owed 2,000 sats; smaller amounts carry to the next block (its own terms; not verified)"),
        // Removed 2026-10-23 (rule 4): 7 of its blocks after a Mac's first accepted share
        // (11 shares, ~180 sats a block) paid it nothing, and nothing was recorded as owed.
        DatumPool(id: "riptide", name: "RIPTIDE", host: "riptide.maveth.ca", port: 29120,
                  pubkey: "b95abf4a11050c5164d09e9d3c4a18a4df735c5d670e3e974fc146794efa4ed9fbc78e7cd4b6abcd3fcc0e0619543d60004fdb49e9d2974582ae11988a03d743",
                  fee: "0% coinbase fee (see website)", website: "https://tides.maveth.ca", minDifficulty: 2048,
                  note: "No longer built in: RIPTIDE didn't credit a Mac. Over 7 of its blocks, a Mac's part (about 180 sats each, under the 546-sat dust limit) wasn't paid or recorded as owed. The Pools page shows the pools that credit a Mac.",
                  statsAPI: .riptide),
        // Removed 2026-10-17: MIN_PAYOUT in ratum's prime/src/ledger/split.rs drops any miner
        // whose part of a block is under 546 sats from that block's split.
        DatumPool(id: "omega", name: "Omega Pool", host: "omegapool.tech", port: 28915,
                  pubkey: "e0af9254ca56f93666922eb268c57f3d62f0132eb6f204db0d3124efbe74fc58028496951ea1e68041986c274b66dedb9a8dfa689403757a7868084d4355bb63",
                  fee: "0.5%", website: "https://omegapool.tech", minDifficulty: 1024,
                  note: "No longer built in: by design, Omega leaves any miner whose part of a block would be under 546 sats out of that block's payout (it keeps every payout above the dust limit), and amounts aren't carried over. A Mac at about 1 GH/s gets about 55 sats a block, so it isn't paid there. The Pools page shows the pools that credit a Mac.",
                  statsAPI: .omega,
                  payout: "Only to miners whose part of a block is at least 546 sats; the other miners share the rest"),
        DatumPool(id: "dxpool", name: "DXPool", host: "xbt.datum.dxpool.com", port: 28915,
                  pubkey: "13dceb1f532408e88661e613c017e88becf0f0e0f3c06fcbb457b49a5033fe427326610133e943af4d3d0fd083a5b18c93f4364c26e3d71472cfe7dbf0ee5514",
                  fee: "See website", website: "https://www.dxpool.net/help/en/tutorial/dxpool-datum-gateway-mining/",
                  minDifficulty: 16384,
                  note: "No longer built in: in October 2026 DXPool rejected a valid share from this app, no DXPool block was built through DATUM for a week, it requires share difficulty 16,384, and its dashboard showed a 25% fee for small miners. The Pools page shows the current built-in pools."),
        DatumPool(id: "convoy", name: "CONVOY", host: "datum-beta1.mine.convoy.xyz", port: 28915,
                  pubkey: "dbb11fa0c2b5403e4f798fa6071bb97e6079d219598366032fdf2ae01962b13c5e66e2be7d6b008f0b2603f3e6f6fc64768fa786c8129c46d3e30a5867734b62",
                  fee: "1%", website: "https://convoy.xyz", minDifficulty: 16384,
                  note: "No longer built in: CONVOY requires share difficulty 16,384 (about a day per share on a Mac)."),
        DatumPool(id: "xorpool", name: "Xor Pool", host: "datum.xorpool.com", port: 28915,
                  pubkey: "b83aedbba54ba2aa605c76859d97aebd16dece3284402b9fc874778a974da4acbb449f6ccda61625d700036f0487a05f5184f79a07abf2880da77352f4cc487e",
                  fee: "1%", website: "https://xorpool.com",
                  note: "No longer built in: Xor Pool found no blocks in the week checked."),
        DatumPool(id: "tyger", name: "Tyger Pool", host: "tygerpool.com", port: 28915,
                  pubkey: "8918e6a6437f9238118da5ce657f90b866dd4d31820d07e798ccd1b8986804ae36d1e494e919fa5e0ba251aec1c631e260f89628ebe6ebafc4b276554f295c3f",
                  fee: "0% (launch)", website: "https://tygerpool.com",
                  note: "No longer built in: Tyger Pool found no blocks in the week checked."),
    ]

    /// A built-in pool by id.
    public static func find(_ id: String) -> DatumPool? { all.first { $0.id == id } }

    /// Problems with a pool you entered, in plain words; empty if it can be used.
    public var problems: [String] {
        var list = [String]()
        let host = self.host.trimmingCharacters(in: .whitespaces)
        let hostOK = !host.isEmpty && host.allSatisfy { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" || $0 == ":" || $0 == "[" || $0 == "]" }
        if !hostOK { list.append("Enter the pool's DATUM server host name, e.g. datum.example.com") }
        if !(1...65535).contains(port) { list.append("Enter the DATUM port (usually 28915)") }
        let hex = pubkey.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if hex.count != 128 || !hex.allSatisfy(\.isHexDigit) {
            list.append("Enter the pool's public key: 128 hex digits from the pool's website")
        }
        return list
    }
}

/// A pool's public gateway that miners connect to directly over Stratum.
/// The pool's node builds the blocks, so this is the least decentralized option.
/// Each one was checked with `b2bminer probe` (connect, subscribe, authorize
/// and parse a live job) before being listed.
public struct HostedGateway: Identifiable, Hashable {
    public let id: String
    public let name: String
    public let url: String
    public let fee: String
    public let website: String
    public let note: String
    /// The pool's public API for your address's statistics, if it has one.
    public var statsAPI: PoolStatsAPI?
    /// How and from what amount the pool pays.
    public var payout: String?

    /// The same rules as the built-in DATUM pools: blocks in the last 7 days, a low
    /// share difficulty, live status (https://b2pool.io/api/v1/stats).
    /// None: the app only suggests pools where your own node builds the blocks. Any
    /// pool's Stratum server can still be entered as a custom server.
    public static let all: [HostedGateway] = []

    /// Gateways that were built in before (until 2026-10-23), still recognized for
    /// their name and statistics when someone has one configured.
    static let known: [HostedGateway] = b2pool

    /// B2Pool's CPU ports: share difficulty from 1, so shares (and the pool's own
    /// verdict on each) come within seconds. Add "d=N" as the password to set a
    /// difficulty. Each region checked with `b2bminer probe` and mined against.
    private static let b2pool: [HostedGateway] = [
        ("de", "Frankfurt"), ("hel", "Helsinki"), ("ord", "Chicago"), ("lax", "Los Angeles"), ("ua", "Kyiv"), ("hkg", "Hong Kong"),
    ].map { region, city in
        HostedGateway(id: "b2pool-\(region)", name: "B2Pool (\(city))", url: "\(region).b2pool.io:5555",
                      fee: "See website", website: "https://b2pool.io",
                      note: "CPU port, share difficulty from 1. The pool's node builds the blocks.", statsAPI: .b2pool,
                      payout: "In a found block's coinbase, nothing to withdraw; no minimum published")
    }
}

extension HostedGateway {
    /// The built-in gateway at this server, however it's written ("de.b2pool.io:5555",
    /// "stratum+tcp://DE.b2pool.io:5555/").
    public static func find(url: String) -> HostedGateway? {
        func key(_ url: String) -> String? {
            var c = StratumConfig()
            c.url = url
            return (try? c.endpoint()).map { "\($0.host.lowercased()):\($0.port)" }
        }
        guard let wanted = key(url) else { return nil }
        return (all + known).first { key($0.url) == wanted }
    }

    public var websiteURL: URL? { webURL(website) }
}

extension DatumPool {
    public var websiteURL: URL? { webURL(website) }
}

/// A web page to open: http(s) only, since a custom pool's website is typed in.
func webURL(_ text: String) -> URL? {
    guard let url = URL(string: text.trimmingCharacters(in: .whitespaces)),
          ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return nil }
    return url
}

extension PoolStatsAPI {
    /// The built-in pool with this statistics API: its name and website.
    /// Retired pools included: you may still have a record or balance there.
    public var poolName: String {
        datumPool?.name ?? HostedGateway.known.first { $0.statsAPI == self }.map { _ in "B2Pool" } ?? rawValue
    }

    public var website: URL? {
        datumPool?.websiteURL ?? HostedGateway.known.first { $0.statsAPI == self }?.websiteURL
    }

    private var datumPool: DatumPool? { (DatumPool.all + DatumPool.retired).first { $0.statsAPI == self } }
}
