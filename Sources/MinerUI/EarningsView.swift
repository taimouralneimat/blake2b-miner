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
                    Text("Payouts to \(address.isEmpty ? "your payout address" : address), as your own node's wallet records them. Newly mined coins become spendable after 6,481 confirmations, about 45 days.")
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let error = model.earningsError {
                    Callout(icon: "exclamationmark.triangle.fill", tint: .orange, text: error)
                }
                if let summary = model.earnings {
                    totals(summary)
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
                if let pool = model.accountPool {
                    PoolAccountSection(pool: pool.name, website: pool.website, account: model.poolAccount,
                                       updated: model.poolAccountUpdated, error: model.poolAccountError)
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

    private func refresh() {
        Task {
            await model.refreshEarnings()
            if model.accountPool != nil { await model.refreshPoolAccount() }
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
                    BarMark(x: .value("Day", d.day, unit: .day), y: .value("BTC", d.amount))
                        .foregroundStyle(Color.accentColor.opacity(0.5))
                }
                ForEach(cumulative, id: \.day) { d in
                    LineMark(x: .value("Day", d.day, unit: .day), y: .value("BTC", d.total))
                        .foregroundStyle(Color.accentColor)
                        .interpolationMethod(.stepEnd)
                }
            }
            .chartYAxisLabel("BTC")
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

    private func btc(_ v: Double) -> String { String(format: "%.8f BTC", v) }

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
