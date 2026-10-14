import Foundation

/// What a pool reports about your payout address, from its public API. Pools
/// report different things; a field is nil when a pool doesn't report it.
public struct PoolAccount: Equatable {
    /// The pool sees work from you right now.
    public var online: Bool?
    /// Your hashrate as the pool measures it (H/s).
    public var hashrate: Double?
    /// Accepted and rejected shares, over `sharesPeriod` (e.g. "24 h").
    public var shares: Int?
    public var rejected: Int?
    public var sharesPeriod: String?
    /// Your share of the pool's payout window (percent).
    public var windowPercent: Double?
    /// What a pool block found now would pay you (BTC).
    public var nextBlockPayout: Double?
    /// Balances (BTC): earned but not yet paid, waiting for coinbase maturity, paid.
    public var unpaid: Double?
    public var immature: Double?
    public var paid: Double?
    /// The pool's estimate of your earnings per day (BTC).
    public var perDay: Double?
    /// The pool has never seen this address.
    public var unknown = false

    public init() {}
}

/// Which public API a pool has for per-address statistics.
public enum PoolStatsAPI: String, Codable, Equatable {
    case lazarus, omega, riptide, b2pool

    /// Your account at the pool. Throws on network or format problems.
    public func account(for address: String) async throws -> PoolAccount {
        let address = Self.address(fromUsername: address)
        switch self {
        case .lazarus: return try await Self.lazarus(address)
        case .omega: return try await Self.omega(address)
        case .riptide: return try await Self.riptide(address)
        case .b2pool: return try await Self.b2pool(address)
        }
    }

    /// The address part of a Stratum username ("address.worker").
    public static func address(fromUsername user: String) -> String {
        String(user.prefix { $0 != "." }).trimmingCharacters(in: .whitespaces)
    }

    // MARK: Pools

    private static func lazarus(_ address: String) async throws -> PoolAccount {
        let d = try await json("https://pool.lazarus-xbt.xyz/api/miner/\(address)")
        var a = PoolAccount()
        a.unknown = d["known"] as? Bool == false
        a.online = d["online"] as? Bool
        a.hashrate = (d["hr_ghs"] as? Double).map { $0 * 1e9 }
        a.shares = d["shares_acc"] as? Int
        a.rejected = d["shares_rej"] as? Int
        a.sharesPeriod = "in the window"
        a.windowPercent = d["window_percent"] as? Double
        a.nextBlockPayout = d["block_payout_btc"] as? Double
        a.unpaid = d["unpaid_btc"] as? Double
        a.immature = d["immature_btc"] as? Double
        a.paid = d["paid_btc"] as? Double
        a.perDay = d["est_btc_day"] as? Double
        return a
    }

    /// Omega lists every miner in its payout window in its pool statistics.
    private static func omega(_ address: String) async throws -> PoolAccount {
        let d = try await json("https://omegapool.tech/stats.json")
        let miners = (d["window"] as? [String: Any])?["miners"] as? [[String: Any]] ?? []
        var a = PoolAccount()
        guard let me = miners.first(where: { ($0["identity"] as? String) == address }) else {
            a.unknown = true
            return a
        }
        a.hashrate = me["hashrate_hs"] as? Double
        a.online = a.hashrate.map { $0 > 0 }
        a.windowPercent = me["share_percent"] as? Double
        a.nextBlockPayout = (me["payout_sats"] as? Double).map { $0 / 1e8 }
        return a
    }

    private static func riptide(_ address: String) async throws -> PoolAccount {
        let d = try await json("https://tides.maveth.ca/api/user/\(address)", notFoundIsEmpty: true)
        var a = PoolAccount()
        guard d["address"] != nil else {
            a.unknown = true
            return a
        }
        a.windowPercent = d["share_pct"] as? Double
        a.nextBlockPayout = (d["estimated_next_sats"] as? Double).map { $0 / 1e8 }
        a.unpaid = (d["unpaid_pending_sats"] as? Double).map { $0 / 1e8 }
        a.paid = (d["total_earned_sats"] as? Double).map { $0 / 1e8 }
        a.online = (d["workers"] as? [Any]).map { !$0.isEmpty }
        return a
    }

    private static func b2pool(_ address: String) async throws -> PoolAccount {
        let d = try await json("https://b2pool.io/api/v1/miner/\(address)")
        var a = PoolAccount()
        a.unknown = d["found"] as? Bool == false
        a.hashrate = (d["hashrate"] as? [String: Any])?["h1"] as? Double
        a.online = (d["workers_online"] as? Int).map { $0 > 0 }
        a.shares = d["shares_24h"] as? Int
        a.rejected = d["rejects_24h"] as? Int
        a.sharesPeriod = "in 24 h"
        let balance = d["balance"] as? [String: Any] ?? [:]
        a.unpaid = (balance["available_sats"] as? Double).map { $0 / 1e8 }
        a.immature = (balance["immature_sats"] as? Double).map { $0 / 1e8 }
        a.paid = (balance["paid_sats"] as? Double).map { $0 / 1e8 }
        a.perDay = ((d["estimate"] as? [String: Any])?["per_day_sats"] as? Double).map { $0 / 1e8 }
        return a
    }

    // MARK: HTTP

    private static func json(_ url: String, notFoundIsEmpty: Bool = false) async throws -> [String: Any] {
        guard let u = URL(string: url) else { throw MinerError.config("Bad pool API address") }
        var request = URLRequest(url: u)
        request.setValue(Miner.userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 404 && notFoundIsEmpty { return [:] }
        guard status == 200, let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MinerError.config("The pool's API answered HTTP \(status)")
        }
        return object
    }
}
