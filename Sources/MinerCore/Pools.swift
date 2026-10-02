import Foundation

/// Pools for the BLAKE2b chain that accept direct connections from miners
/// through a public DATUM gateway (the Stratum dialect this miner speaks).
/// Each one was checked with `b2bminer probe` (connect, subscribe, authorize and
/// parse a live job) before being listed. Pools set their own share difficulty;
/// at CPU speed a share can take days.
public struct PoolPreset: Identifiable, Hashable {
    public let id: String
    public let name: String
    public let url: String
    public let fee: String
    public let website: String
    public let note: String

    public static let all: [PoolPreset] = [
        PoolPreset(id: "dxpool", name: "DXPool", url: "xbt.public-gateway-01.dxpool.com:23334",
                   fee: "see dxpool.net", website: "https://www.dxpool.net/help/en/tutorial/dxpool-datum-gateway-mining/",
                   note: "Public DATUM gateway; payouts go straight to your address from the coinbase."),
        PoolPreset(id: "xorpool", name: "Xor Pool (US)", url: "stratum+ssl://datum.xorpool.com:23337",
                   fee: "2% (pool-built blocks)", website: "https://xorpool.com",
                   note: "Shared payout straight from the coinbase. TLS encrypted."),
        PoolPreset(id: "xorpool-eu", name: "Xor Pool (Europe)", url: "stratum+ssl://eu.datum.xorpool.com:23337",
                   fee: "2% (pool-built blocks)", website: "https://xorpool.com",
                   note: "Shared payout straight from the coinbase. TLS encrypted."),
        PoolPreset(id: "xorpool-hk", name: "Xor Pool (Asia)", url: "stratum+ssl://hk.datum.xorpool.com:23337",
                   fee: "2% (pool-built blocks)", website: "https://xorpool.com",
                   note: "Shared payout straight from the coinbase. TLS encrypted."),
    ]
}
