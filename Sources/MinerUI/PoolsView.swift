import MinerCore
import SwiftUI

/// The Pools page: how big each built-in pool is, so you can mine where your
/// hashrate helps decentralize the network.
struct PoolsView: View {
    @EnvironmentObject var model: AppModel

    private static let largeShare = PoolOverview.tooLarge

    private struct Row: Identifiable {
        let id: String
        let name: String
        let youBuild: Bool
        let fee: String
        let minDifficulty: Double?
        let website: URL?
        let payout: String?
        let isCurrent: Bool
        let datumPool: DatumPool?
        /// What's being tested, for a pool under evaluation.
        var testing: String? = nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Pools").font(.largeTitle.weight(.semibold))
                    Text("Every built-in DATUM pool found blocks in the last week, accepts shares at a low difficulty, publishes live status, and credits a small miner's work instead of dropping it. Choosing a smaller pool keeps any single pool from controlling the network. With DATUM, your own node builds the blocks whichever pool you choose.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                RestartBanner()
                ForEach(rows) { row in card(row) }
                if !evaluationRows.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Under evaluation").font(.title2.weight(.semibold))
                        Text("Pools being tested on a real Mac before they're built in. You can join a test; your node still builds the blocks.")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 8)
                    ForEach(evaluationRows) { row in card(row) }
                }
                HStack {
                    if let updated = model.poolOverviewsUpdated {
                        Text("Updated \(updated, style: .relative) ago").foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Refresh") { Task { await model.refreshPoolOverviews() } }
                    Button("Add a Custom Pool…") { model.page = .mining }
                }
                .font(.callout)
            }
            .padding(28)
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
        }
        .task { await model.refreshPoolOverviewsIfStale() }
    }

    private var rows: [Row] {
        let c = model.config
        let datum = DatumPool.all.map { p in
            Row(id: p.id, name: p.name, youBuild: true, fee: p.fee, minDifficulty: p.minDifficulty, website: p.websiteURL,
                payout: p.payout, isCurrent: c.mode == .datum && c.gateway.poolID == p.id, datumPool: p)
        }
        return datum
    }

    private var evaluationRows: [Row] {
        let c = model.config
        return DatumPool.underEvaluation.map { e in
            Row(id: e.pool.id, name: e.pool.name, youBuild: true, fee: e.pool.fee, minDifficulty: e.pool.minDifficulty,
                website: e.pool.websiteURL, payout: e.pool.payout,
                isCurrent: c.mode == .datum && c.gateway.poolID == e.pool.id, datumPool: e.pool, testing: e.testing)
        }
    }

    /// Only one built-in DATUM pool: a large one can't be "not recommended" in favor of none.
    private var noBuiltInAlternative: Bool { DatumPool.all.count < 2 }

    /// The smallest pool by network share that your own node builds blocks with.
    private var smallestDatumPool: String? {
        guard rows.filter(\.youBuild).count > 1 else { return nil }  // "smallest" of one means nothing
        return rows.filter(\.youBuild)
            .compactMap { r in model.poolOverviews[r.id]?.networkShare.map { (r.id, $0) } }
            .min { $0.1 < $1.1 }?.0
    }

    private func card(_ row: Row) -> some View {
        let overview = model.poolOverviews[row.id]
        let share = overview?.networkShare
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(row.name).font(.title3.weight(.semibold))
                BuilderBadge(youBuild: row.youBuild, compact: true)
                if row.isCurrent { tag("Mining here", .accentColor) }
                if row.testing != nil { tag("Testing", .purple) }
                if let share = share, share > Self.largeShare {
                    tag(noBuiltInAlternative && row.testing == nil ? "Large" : "Not recommended", .orange)
                }
                if row.id == smallestDatumPool { tag("Smallest", .green) }
                Spacer()
                if let website = row.website { Link("Website", destination: website) }
                if let pool = row.datumPool, !row.isCurrent {
                    Button(row.testing == nil ? "Use This Pool" : "Join the Test") { use(pool) }
                }
            }
            HStack(spacing: 10) {
                ShareBar(share: share ?? 0, tint: share.map { $0 > Self.largeShare ? .orange : .green } ?? .secondary)
                    .frame(width: 260, height: 8)
                Text(share.map { String(format: "%.1f%% of the network", $0 * 100) } ?? (model.poolOverviewsUpdated == nil ? "Asking the pool…" : "Size not reported"))
                    .monospacedDigit()
            }
            .font(.callout)
            Text(details(row, overview)).font(.callout).foregroundStyle(.secondary)
            if let payout = row.payout {
                Label("Payout: " + payout, systemImage: "bitcoinsign.circle").font(.callout).foregroundStyle(.secondary)
            }
            if let testing = row.testing {
                Label(testing, systemImage: "flask").font(.callout).foregroundStyle(.purple)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let share = share, share > Self.largeShare {
                Text(noBuiltInAlternative && row.testing == nil
                     ? "Over 20% of the network's hashrate. It's the only pool verified to credit a Mac's small amounts; smaller pools are being tested below. Solo mining is the alternative that doesn't add to any pool."
                     : "Not recommended: over 20% of the network's hashrate. " + PoolOverview.tooLargeAdvice)
                    .font(.caption).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 16))
    }

    private func details(_ row: Row, _ overview: PoolOverview?) -> String {
        var parts = ["Fee: \(row.fee)"]
        if let d = row.minDifficulty { parts.append("share difficulty from \(Int(d).formatted())") }
        if let m = overview?.miners { parts.append("\(m) miners") }
        if let b = overview?.blocks7d { parts.append("\(b) blocks in 7 days") }
        if !row.youBuild { parts.append("the pool's node builds the blocks") }
        return parts.joined(separator: " · ")
    }

    private func tag(_ text: String, _ tint: Color) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 7).padding(.vertical, 2)
            .foregroundStyle(tint)
            .background(tint.opacity(0.14), in: Capsule())
    }

    /// Mines with `pool` through your own gateway (from the next start or restart).
    /// Mines with `pool`; a pool under evaluation is added to your pools first.
    private func use(_ pool: DatumPool) {
        if !model.config.gateway.pools.contains(where: { $0.id == pool.id }) {
            model.config.gateway.customPools.append(pool)
        }
        if model.config.mode == .stratum && model.config.payoutAddress.trimmingCharacters(in: .whitespaces).isEmpty {
            model.config.payoutAddress = PoolStatsAPI.address(fromUsername: model.config.stratum.user)
        }
        model.config.mode = .datum
        model.config.gateway.poolID = pool.id
    }
}

/// A pool's share of the network as a bar (a ProgressView ignores its tint on macOS).
private struct ShareBar: View {
    let share: Double
    let tint: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule().fill(tint).frame(width: max(geo.size.height, geo.size.width * min(share, 1)))
            }
        }
    }
}
