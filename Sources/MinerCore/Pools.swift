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

    public init(id: String, name: String, host: String, port: Int, pubkey: String, fee: String, website: String,
                minDifficulty: Double? = nil, note: String? = nil) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.pubkey = pubkey
        self.fee = fee
        self.website = website
        self.minDifficulty = minDifficulty
        self.note = note
    }

    /// Built-in pools meet three rules, checked on 2026-10-10: they found blocks in the
    /// last 7 days (by their coinbase tags on the chain), their DATUM server accepts
    /// shares at a low difficulty (measured through the bundled gateway), and they
    /// publish live status. Any other pool can be added as a custom pool.
    public static let all: [DatumPool] = [
        // 201 blocks in the 7 days; status API at https://pool.lazarus-xbt.xyz/api/pool.
        DatumPool(id: "lazarus", name: "Lazarus", host: "datum.lazarus-xbt.xyz", port: 28915,
                  pubkey: "29120606bbbfdeb0dcb259d13ed1fba9e6ff198ff6a0152cffb7608dc1c266bd17532393738aee7edf9aa0c9ec93b835256971f186da878f77fb3ed273dff30a",
                  fee: "0% through your own gateway", website: "https://pool.lazarus-xbt.xyz", minDifficulty: 1024),
        // 57 blocks; status at https://omegapool.tech/stats.json.
        DatumPool(id: "omega", name: "Omega Pool", host: "omegapool.tech", port: 28915,
                  pubkey: "e0af9254ca56f93666922eb268c57f3d62f0132eb6f204db0d3124efbe74fc58028496951ea1e68041986c274b66dedb9a8dfa689403757a7868084d4355bb63",
                  fee: "0.5%", website: "https://omegapool.tech", minDifficulty: 1024),
        // 22 blocks; status at https://tides.maveth.ca/api/stats.
        DatumPool(id: "riptide", name: "RIPTIDE", host: "riptide.maveth.ca", port: 29120,
                  pubkey: "b95abf4a11050c5164d09e9d3c4a18a4df735c5d670e3e974fc146794efa4ed9fbc78e7cd4b6abcd3fcc0e0619543d60004fdb49e9d2974582ae11988a03d743",
                  fee: "0% coinbase fee (see website)", website: "https://tides.maveth.ca", minDifficulty: 2048),
    ]

    /// Pools that were built in before and no longer meet the rules. A saved choice of
    /// one is kept as a custom pool, so nothing changes silently.
    static let retired: [DatumPool] = [
        DatumPool(id: "dxpool", name: "DXPool", host: "xbt.datum.dxpool.com", port: 28915,
                  pubkey: "13dceb1f532408e88661e613c017e88becf0f0e0f3c06fcbb457b49a5033fe427326610133e943af4d3d0fd083a5b18c93f4364c26e3d71472cfe7dbf0ee5514",
                  fee: "See website", website: "https://www.dxpool.net/help/en/tutorial/dxpool-datum-gateway-mining/",
                  minDifficulty: 16384,
                  note: "No longer built in: in October 2026 DXPool rejected a valid share from this app, no DXPool block was built through DATUM for a week, it requires share difficulty 16,384, and its dashboard showed a 25% fee for small miners. Lazarus or Omega Pool are recommended."),
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

    /// The same rules as the built-in DATUM pools: blocks in the last 7 days, a low
    /// share difficulty, live status (https://b2pool.io/api/v1/stats).
    public static let all: [HostedGateway] = b2pool

    /// B2Pool's CPU ports: share difficulty from 1, so shares (and the pool's own
    /// verdict on each) come within seconds. Add "d=N" as the password to set a
    /// difficulty. Each region checked with `b2bminer probe` and mined against.
    private static let b2pool: [HostedGateway] = [
        ("de", "Frankfurt"), ("hel", "Helsinki"), ("ord", "Chicago"), ("lax", "Los Angeles"), ("ua", "Kyiv"), ("hkg", "Hong Kong"),
    ].map { region, city in
        HostedGateway(id: "b2pool-\(region)", name: "B2Pool (\(city))", url: "\(region).b2pool.io:5555",
                      fee: "See website", website: "https://b2pool.io",
                      note: "CPU port, share difficulty from 1. The pool's node builds the blocks.")
    }
}

extension HostedGateway {
    public static func find(url: String) -> HostedGateway? { all.first { $0.url == url } }
}

extension DatumPool {
    public var websiteURL: URL? { URL(string: website) }
}

extension HostedGateway {
    public var websiteURL: URL? { URL(string: website) }
}
