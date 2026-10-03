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

    public static let all: [HostedGateway] = [
        HostedGateway(id: "dxpool", name: "DXPool", url: "xbt.public-gateway-01.dxpool.com:23334",
                   fee: "see dxpool.net", website: "https://www.dxpool.net/help/en/tutorial/dxpool-datum-gateway-mining/",
                   note: "Public DATUM gateway; payouts go straight to your address from the coinbase."),
        HostedGateway(id: "xorpool", name: "Xor Pool (US)", url: "stratum+ssl://datum.xorpool.com:23337",
                   fee: "2% (pool-built blocks)", website: "https://xorpool.com",
                   note: "Shared payout straight from the coinbase. TLS encrypted."),
        HostedGateway(id: "xorpool-eu", name: "Xor Pool (Europe)", url: "stratum+ssl://eu.datum.xorpool.com:23337",
                   fee: "2% (pool-built blocks)", website: "https://xorpool.com",
                   note: "Shared payout straight from the coinbase. TLS encrypted."),
        HostedGateway(id: "xorpool-hk", name: "Xor Pool (Asia)", url: "stratum+ssl://hk.datum.xorpool.com:23337",
                   fee: "2% (pool-built blocks)", website: "https://xorpool.com",
                   note: "Shared payout straight from the coinbase. TLS encrypted."),
    ]
}

extension HostedGateway {
    public static func find(url: String) -> HostedGateway? { all.first { $0.url == url } }
}
