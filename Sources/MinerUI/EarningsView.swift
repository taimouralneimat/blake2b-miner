import Charts
import MinerCore
import SwiftUI

/// The Earnings page: payouts to your address, read from your own node's wallet,
/// and what the pool says you have earned.
struct EarningsView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Earnings").font(.largeTitle.weight(.semibold))
                    Text("Payouts to \(address.isEmpty ? "your payout address" : address), as your own node's wallet records them. Mined coins can be spent through your node after 6,481 confirmations, about 45 days.")
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let error = model.earningsError {
                    Callout(icon: "exclamationmark.triangle.fill", tint: .orange, text: error)
                }
                if let summary = model.earnings { totals(summary) }
                pools
                if let summary = model.earnings {
                    if summary.payouts.isEmpty {
                        Text("No payouts to this address yet. Payouts appear here when a pool you mine with (or you, solo) finds a block that pays you.")
                            .foregroundStyle(.secondary)
                    } else {
                        chart(summary.payouts)
                        list(summary.payouts)
                    }
                } else if model.earningsChecked {
                    Text("No wallet loaded in your node has this address, so the app can't see payouts to it. To follow them here, load the wallet that has the address in Bitcoin Knots, or import the address as watch-only (importaddress, or importdescriptors with addr(…)).")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Reading your node's wallet…").foregroundStyle(.secondary)
                }
                HStack {
                    Spacer()
                    Button("Refresh") { refresh() }
                }
            }
            .padding(28)
            .frame(maxWidth: 1000)
            .frame(maxWidth: .infinity)
        }
        .task { refresh() }
    }

    private var address: String { model.accountPool?.address ?? model.config.payoutAddress }

    /// Your wallet and the pool you mine with; other pools only on their own button.
    private func refresh() {
        Task {
            await model.refreshEarnings()
            if model.accountPool != nil { await model.refreshPoolAccount() }
            await model.discoverPools()
        }
    }

    /// The pool you mine with (live), then any pool you left that still owes you something;
    /// one that owes nothing is left out, since nothing more will come from it.
    @ViewBuilder private var pools: some View {
        let current = model.accountPool
        let others = model.poolRecords.filter { r in
            !(current.map { $0.api == r.api && $0.address == r.address } ?? false) && (r.account?.owed ?? 0) > 0
        }
        let owed = (model.poolAccount?.owed ?? 0) + others.reduce(0) { $0 + ($1.account?.owed ?? 0) }
        if current != nil || !others.isEmpty {
            HStack(alignment: .firstTextBaseline) {
                Text("At the pools").font(.title2.weight(.semibold))
                Spacer()
                if owed > 0 {
                    Text("Pools owe you \(formatAmount(owed))").font(.headline).monospacedDigit()
                }
            }
            .padding(.top, 6)
        }
        if let pool = current {
            PoolAccountSection(pool: pool.name, website: pool.website, account: model.poolAccount,
                               updated: model.poolAccountUpdated, error: model.poolAccountError,
                               role: model.isRunning ? "· mining now" : "· your pool")
        }
        ForEach(others) { r in
            PoolAccountSection(pool: r.api.poolName, website: r.api.website, account: r.account, updated: nil,
                               error: nil, role: r.address == address ? "· not mining here now" : "· address \(r.address.prefix(10))…",
                               checked: r.updated, checkNow: { Task { await model.refresh(r) } })
        }
    }

    private func totals(_ s: Earnings.Summary) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 14)], spacing: 14) {
            StatTile(title: "Spendable", value: btc(s.spendable), detail: "in wallet “\(s.wallet)”", detailTint: nil)
            StatTile(title: "Maturing", value: btc(s.maturing), detail: "not spendable yet", detailTint: nil)
            StatTile(title: "Payouts", value: "\(s.payouts.count)", detail: s.payouts.first.map { "last \(Self.date.string(from: $0.time))" }, detailTint: nil)
        }
    }

    private func chart(_ payouts: [Earnings.Payout]) -> some View {
        let byDay = Dictionary(grouping: payouts.filter { $0.status != .orphaned }) { Calendar.current.startOfDay(for: $0.time) }
            .map { (day: $0.key, amount: $0.value.reduce(0) { $0 + $1.amount }) }
            .sorted { $0.day < $1.day }
        var running = 0.0
        let cumulative = byDay.map { d -> (day: Date, total: Double) in
            running += d.amount
            return (d.day, running)
        }
        return VStack(alignment: .leading, spacing: 10) {
            Text("Total earned").font(.headline)
            Chart {
                ForEach(byDay, id: \.day) { d in
                    BarMark(x: .value("Day", d.day, unit: .day), y: .value("sats", d.amount * 1e8))
                        .foregroundStyle(Color.accentColor.opacity(0.5))
                }
                ForEach(cumulative, id: \.day) { d in
                    LineMark(x: .value("Day", d.day, unit: .day), y: .value("sats", d.total * 1e8))
                        .foregroundStyle(Color.accentColor)
                        .interpolationMethod(.stepEnd)
                }
            }
            .chartYAxisLabel("sats")
            .frame(minHeight: 200)
        }
        .padding(18)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 16))
    }

    private func list(_ payouts: [Earnings.Payout]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Payouts").font(.headline)
            ForEach(payouts) { p in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(Self.date.string(from: p.time)).monospacedDigit()
                        Text(btc(p.amount)).monospacedDigit().fontWeight(.medium)
                        Spacer()
                        Text(p.txid.prefix(16) + "…").font(.caption.monospaced()).foregroundStyle(.secondary)
                            .textSelection(.enabled).help(p.txid)
                    }
                    Text(status(p)).font(.caption).foregroundStyle(p.status == .orphaned ? .orange : .secondary)
                }
                .font(.callout)
                Divider()
            }
        }
        .padding(18)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 16))
    }

    private func status(_ p: Earnings.Payout) -> String {
        switch p.status {
        case .spendable: return "spendable"
        case .maturing:
            let when = p.spendableAround.map { ", spendable around \(Self.day.string(from: $0))" } ?? ""
            return "maturing (\(p.confirmations.formatted()) of \(p.confirmationsNeeded.formatted()) confirmations\(when))"
        case .orphaned: return "orphaned: its block left the chain"
        }
    }

    private func btc(_ v: Double) -> String { formatAmount(v) }

    private static let day: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f
    }()

    private static let date: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()
}
