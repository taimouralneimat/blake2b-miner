import MinerCore
import SwiftUI

/// The Pools page: how big each built-in pool is, so you can mine where your
/// hashrate helps decentralize the network.
struct PoolsView: View {
    @EnvironmentObject var model: AppModel

    /// A pool above this share of the network is called large.
    private static let largeShare = 0.2

    private struct Row: Identifiable {
        let id: String
        let name: String
        let youBuild: Bool
        let fee: String
        let minDifficulty: Double?
        let website: URL?
        let isCurrent: Bool
        let datumPool: DatumPool?
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Pools").font(.largeTitle.weight(.semibold))
                    Text("Every pool here found blocks in the last week and accepts shares at a low difficulty. Pools pay alike over time, so choosing a smaller one costs you little and keeps any single pool from controlling the network. With DATUM, your own node builds the blocks whichever pool you choose.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(rows) { row in card(row) }
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
        .task {
            if model.poolOverviewsUpdated.map({ Date().timeIntervalSince($0) > 300 }) ?? true {
                await model.refreshPoolOverviews()
            }
        }
    }

    private var rows: [Row] {
        let c = model.config
        let datum = DatumPool.all.map { p in
            Row(id: p.id, name: p.name, youBuild: true, fee: p.fee, minDifficulty: p.minDifficulty, website: p.websiteURL,
                isCurrent: c.mode == .datum && c.gateway.poolID == p.id, datumPool: p)
        }
        let b2pool = HostedGateway.all.first.map { g in
            Row(id: "b2pool", name: "B2Pool", youBuild: false, fee: g.fee, minDifficulty: 1, website: g.websiteURL,
                isCurrent: c.mode == .stratum && HostedGateway.find(url: c.stratum.url)?.statsAPI == .b2pool, datumPool: nil)
        }
        return datum + (b2pool.map { [$0] } ?? [])
    }

    /// The smallest pool by network share that your own node builds blocks with.
    private var smallestDatumPool: String? {
        rows.filter(\.youBuild)
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
                if let share = share, share > Self.largeShare { tag("Large", .orange) }
                if row.id == smallestDatumPool { tag("Smallest", .green) }
                Spacer()
                if let website = row.website { Link("Website", destination: website) }
                if let pool = row.datumPool, !row.isCurrent {
                    Button("Use This Pool") { use(pool) }
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
            if let share = share, share > Self.largeShare {
                Text("Over a fifth of the network's hashrate. Mining with a smaller pool spreads the hashrate more widely.")
                    .font(.caption).foregroundStyle(.orange)
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
    private func use(_ pool: DatumPool) {
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
