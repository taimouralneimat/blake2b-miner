import Foundation

/// What a pool reports about your payout address, from its public API. Pools
/// report different things; a field is nil when a pool doesn't report it.
public struct PoolAccount: Equatable, Codable {
    /// The pool has seen work from you recently (for a slow miner, shares are
    /// rare, so this is often false while mining normally).
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
    /// Everything the pool has credited you, paid or not (BTC).
    public var earned: Double?
    /// Earned but too small to pay yet: carried until it reaches `minimumPayout` (BTC).
    public var carried: Double?
    public var minimumPayout: Double?
    /// The pool's estimate of your earnings per day (BTC).
    public var perDay: Double?
    /// The pool has never seen this address.
    public var unknown = false
    /// Why the pool won't pay you yet, when it says (e.g. under its minimum).
    public var notice: String?

    /// What the pool owes you and hasn't paid: unpaid, carried below the minimum,
    /// and waiting for coinbase maturity.
    public var owed: Double { (unpaid ?? 0) + (carried ?? 0) + (immature ?? 0) }

    public init() {}
}

/// A pool's size, for choosing one that keeps the network decentralized.
public struct PoolOverview: Equatable {
    /// The pool's share of the network's hashrate (0...1).
    public var networkShare: Double?
    /// Miners connected or in the payout window, as the pool counts them.
    public var miners: Int?
    /// Blocks the pool found in the last 7 days, when it reports them.
    public var blocks7d: Int?

    /// Above this share of the network's hashrate a pool isn't recommended.
    public static let tooLarge = 0.2
    public static let tooLargeAdvice = "BLAKE2b Miner is here for decentralization, so please mine with a smaller pool; pools pay alike over time."

    public init(networkShare: Double? = nil, miners: Int? = nil, blocks7d: Int? = nil) {
        self.networkShare = networkShare
        self.miners = miners
        self.blocks7d = blocks7d
    }
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

    /// The pool's size: its share of the network, and its miners.
    public func overview() async throws -> PoolOverview {
        var o = PoolOverview()
        switch self {
        case .lazarus:
            let d = try await Self.json("https://pool.lazarus-xbt.xyz/api/pool")
            o.networkShare = d["pool_share"] as? Double
            o.miners = d["miners_online"] as? Int
        case .omega:
            let d = try await Self.json("https://omegapool.tech/stats.json")
            o.networkShare = (d["hashrate"] as? [String: Any])?["pool_share"] as? Double
            o.miners = ((d["window"] as? [String: Any])?["miners"] as? [Any])?.count
        case .riptide:
            let d = try await Self.json("https://tides.maveth.ca/api/stats")
            o.blocks7d = d["blocks_last_7d"] as? Int
            // Its hashrate share; blocks found / ~1,008 a week is the fallback (luck skews it).
            o.networkShare = (d["pool_network_share_pct"] as? Double).map { $0 / 100 } ?? o.blocks7d.map { Double($0) / 1008 }
            o.miners = d["addresses_in_window"] as? Int
        case .b2pool:
            let d = try await Self.json("https://b2pool.io/api/v1/stats")
            let main = (d["chains"] as? [String: Any])?["mainnet"] as? [String: Any] ?? [:]
            let pool = main["pool"] as? [String: Any] ?? [:]
            let hash = ["prop", "solo"].compactMap { Self.number((pool[$0] as? [String: Any])?["pool_hash"]) }.reduce(0, +)
            if let network = Self.number(main["network_hash"]), network > 0 { o.networkShare = hash / network }
            o.miners = d["miners_active"] as? Int
        }
        return o
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
        // "shares_acc" and "shares_rej" are difficulty (work), not counts: one
        // share at difficulty 1,024 adds 1,024. "window_shares" is the count.
        a.shares = d["window_shares"] as? Int
        a.sharesPeriod = "in the payout window"
        // The window holds a fixed amount of pool work; at the pool's hashrate that
        // is a span of time. Older shares have left it, after earning their part.
        if let pool = try? await json("https://pool.lazarus-xbt.xyz/api/pool"),
           let work = number(pool["window_work"]), let ghs = number(pool["pool_hr_ghs"]), ghs > 0 {
            let hours = work * 4_294_967_296 / (ghs * 1e9) / 3600
            a.sharesPeriod = "in the payout window (about the last \(Int(hours.rounded())) h)"
        }
        a.windowPercent = d["window_percent"] as? Double
        a.nextBlockPayout = d["block_payout_btc"] as? Double
        a.unpaid = d["unpaid_btc"] as? Double
        a.immature = d["immature_btc"] as? Double
        a.paid = d["paid_btc"] as? Double
        a.carried = d["carry_btc"] as? Double
        a.minimumPayout = d["min_payout_btc"] as? Double
        a.perDay = d["est_btc_day"] as? Double
        return a
    }

    /// Omega lists every miner in its payout window in its pool statistics.
    private static func omega(_ address: String) async throws -> PoolAccount {
        let d = try await json("https://omegapool.tech/stats.json")
        let miners = (d["window"] as? [String: Any])?["miners"] as? [[String: Any]] ?? []
        // Amounts from found blocks that were too small to pay in their coinbase.
        let owed = ((d["owed"] as? [String: Any])?["by_identity"] as? [[String: Any]] ?? [])
            .first { ($0["identity"] as? String) == address }
        var a = PoolAccount()
        a.unpaid = (owed?["sats"] as? Double).map { $0 / 1e8 }
        guard let me = miners.first(where: { ($0["identity"] as? String) == address }) else {
            a.unknown = owed == nil
            return a
        }
        a.hashrate = me["hashrate_hs"] as? Double
        a.online = a.hashrate.map { $0 > 0 }
        a.windowPercent = me["share_percent"] as? Double
        a.nextBlockPayout = (me["payout_sats"] as? Double).map { $0 / 1e8 }
        if me["payable"] as? Bool == false {
            a.notice = (me["unpayable_reason"] as? String).map { "Not paid in a block yet: \($0)" } ?? "Not paid in a block yet"
        } else if a.nextBlockPayout == 0, (me["work"] as? String).flatMap(Double.init) ?? 0 > 0 {
            // Omega leaves out of a block's split anyone whose part is under 546 sats.
            a.notice = "Your part of a block is under Omega's 546-sat minimum, so you're left out of its payouts, and it isn't carried over: at this hashrate, mining here earns nothing."
        }
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
        a.earned = (d["total_earned_sats"] as? Double).map { $0 / 1e8 }
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
        let window = d["window"] as? [String: Any] ?? [:]
        a.windowPercent = window["share_pct"] as? Double
        a.nextBlockPayout = (window["est_sats"] as? Double).map { $0 / 1e8 }
        return a
    }

    // MARK: HTTP

    /// A JSON number as a Double; large integers (above 2^53) don't bridge with `as?`.
    private static func number(_ v: Any?) -> Double? { (v as? NSNumber)?.doubleValue }

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
