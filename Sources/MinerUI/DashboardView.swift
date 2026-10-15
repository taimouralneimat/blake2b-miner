import Charts
import MinerCore
import SwiftUI

/// The Overview page: everything about the current session, sized for a large
/// or full-screen window.
struct DashboardView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                UpdateBanner(updater: model.updater)
                hero
                if !model.isConfigured {
                    welcome
                } else if case .waiting(let reason)? = model.isRunning ? model.status.state : nil {
                    VStack(alignment: .leading, spacing: 10) {
                        Callout(icon: "pause.circle.fill", tint: .orange, text: reason)
                        HStack {
                            Button("Run Checks") { model.page = .diagnostics }
                            Button("Show Log") { model.page = .log }
                        }
                    }
                }
                if let g = model.status.gatewayStatus, model.isRunning, case .problem = GatewayHint.from(g) {
                    Callout(icon: "exclamationmark.triangle.fill", tint: .orange, text: g)
                }
                if model.isRunning && model.status.poolRejectsEverything {
                    Callout(icon: "xmark.octagon.fill", tint: .orange, text: model.status.poolRejectionWarning)
                }
                if model.isRunning, let warning = model.status.nodeWarning {
                    Callout(icon: "exclamationmark.triangle.fill", tint: .orange, text: warning)
                }
                chartCard
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 14)], spacing: 14) {
                    ForEach(cards, id: \.title) { card in
                        StatTile(title: card.title, value: card.value, detail: card.detail, detailTint: card.tint)
                    }
                }
                if model.isRunning, let pool = model.accountPool {
                    PoolAccountSection(pool: pool.name, website: pool.website, account: model.poolAccount,
                                       updated: model.poolAccountUpdated, error: model.poolAccountError)
                }
                activity
            }
            .padding(28)
            .frame(maxWidth: 1400)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: Hero

    private var hero: some View {
        HStack(alignment: .center, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    StatePill(state: model.isRunning ? model.status.state : .stopped)
                    BuilderBadge(youBuild: model.config.mode.youBuildTheBlocks)
                }
                Text(model.isRunning ? formatHashrate(model.status.hashrate) : "Not mining")
                    .font(.system(size: 52, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(subtitle)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                if model.isRunning, let split = model.status.speedSplit {
                    Text(split)
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            primaryButton
        }
        .padding(22)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 16))
    }

    private var subtitle: String {
        let mode: String
        switch model.config.mode {
        case .datum: mode = "Own DATUM Gateway · " + (model.config.gateway.pool.map { "pooled with \($0.name)" } ?? "solo")
        case .solo: mode = "Solo with your Knots node"
        case .stratum: mode = "Pool-hosted gateway · " + (HostedGateway.find(url: model.config.stratum.url)?.name ?? model.config.stratum.url)
        }
        guard model.isRunning else { return mode }
        return mode + " · average " + formatHashrate(model.status.averageHashrate)
    }

    @ViewBuilder private var primaryButton: some View {
        if !model.isConfigured {
            Button { model.page = .mining } label: { Label("Set Up…", systemImage: "gearshape").padding(.horizontal, 8) }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        } else if model.isRunning {
            Button { model.stop() } label: { Label("Stop Mining", systemImage: "stop.fill").padding(.horizontal, 8) }
                .controlSize(.large)
        } else {
            Button { model.start() } label: { Label("Start Mining", systemImage: "play.fill").padding(.horizontal, 8) }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .controlSize(.large)
        }
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Welcome to BLAKE2b Miner").font(.title2.weight(.semibold))
            Text("To start, open Mining and enter a payout address from your own wallet. Bitcoin Knots needs to be running with its RPC server on; Diagnostics checks your setup.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Open Mining Settings") { model.page = .mining }
                    .buttonStyle(.borderedProminent)
                Button("Run Checks") { model.page = .diagnostics }
            }
            .padding(.top, 4)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: Chart

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Hashrate").font(.headline)
                Text("last hour").foregroundStyle(.secondary)
                Spacer()
            }
            if model.history.count < 2 {
                Text(model.isRunning ? "The chart fills in while you mine (a point every 10 seconds)." : "Start mining to see your hashrate here.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                Chart(model.history) { sample in
                    AreaMark(x: .value("Time", sample.time), y: .value("MH/s", sample.hashrate / 1e6))
                        .foregroundStyle(.linearGradient(colors: [.accentColor.opacity(0.35), .accentColor.opacity(0.02)],
                                                         startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.monotone)
                    LineMark(x: .value("Time", sample.time), y: .value("MH/s", sample.hashrate / 1e6))
                        .foregroundStyle(Color.accentColor)
                        .interpolationMethod(.monotone)
                }
                .chartYAxisLabel("MH/s")
                .chartXAxis { AxisMarks(values: timeMarks) { _ in AxisGridLine(); AxisValueLabel(format: .dateTime.hour().minute()) } }
                .frame(minHeight: 200)
            }
        }
        .padding(18)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: Cards

    private struct Card {
        let title: String
        let value: String
        var detail: String?
        var tint: Color?
    }

    private var cards: [Card] {
        let s = model.status
        var list = [Card]()
        if model.config.mode == .solo {
            list.append(Card(title: "Expected block", value: s.expectedSecondsPerBlock.map { "≈ " + formatDuration($0) } ?? "–",
                             detail: "at the current hashrate"))
            list.append(Card(title: "Height", value: s.height.map { $0.formatted() } ?? "–",
                             detail: s.transactions.map { "\($0) transactions" }))
            list.append(Card(title: "Network difficulty",
                             value: s.networkDifficulty.map { $0.formatted(.number.notation(.compactName).precision(.significantDigits(3))) } ?? "–"))
            list.append(Card(title: "Block reward", value: s.reward.map { String(format: "%.4f", $0) } ?? "–", detail: "BTC, with fees"))
        } else {
            list.append(Card(title: "Next share", value: s.expectedSecondsPerShare.map { "≈ " + formatDuration($0) } ?? "–",
                             detail: "on average"))
            list.append(Card(title: "Shares", value: "\(s.confirmedShares)",
                             detail: s.shareSummary,
                             tint: s.sharesRejected > 0 || s.poolRejected > 0 ? .orange : nil))
            list.append(Card(title: "Share difficulty", value: s.shareDifficulty.map(formatDifficulty) ?? "–", detail: "set by the pool"))
            if model.config.mode == .datum {
                list.append(Card(title: "Pool", value: model.config.gateway.pool?.name ?? "Solo",
                                 detail: poolState))
            }
        }
        let found = model.foundBlocks.filter(\.countsAsFound).count
        list.append(Card(title: "Blocks found", value: "\(found)", detail: found > 0 ? "all time" : "a lottery ticket",
                         tint: found > 0 ? .green : nil))
        // One card for the session, so the grid stays even.
        let config = model.runningConfig ?? model.config
        let priority = config.lowPriority ? "responsive" : "full speed"
        if let start = s.startedAt, model.isRunning {
            list.append(Card(title: "Running for", value: formatDuration(Date().timeIntervalSince(start)),
                             detail: "\(config.hardwareShort), \(priority) · \(formatHashes(s.totalHashes)) hashes"))
        } else {
            list.append(Card(title: "Hardware", value: config.hardwareShort,
                             detail: config.useGPU && config.gpuLoad < 100 ? "\(priority) · GPU at \(config.gpuLoad)%" : priority))
        }
        return list
    }

    private var poolState: String {
        guard model.isRunning, let g = model.status.gatewayStatus else { return "not connected" }
        if g.hasPrefix("Pooled") { return "connected" }
        if g.hasPrefix("Connecting") { return "connecting…" }
        if g.hasPrefix("Pool problem") { return "problem, see Log" }
        return "solo"
    }

    private func formatHashes(_ n: UInt64) -> String {
        n < 1000 ? "\(n)" : Double(n).formatted(.number.notation(.compactName).precision(.significantDigits(3)))
    }

    /// Time labels every 10 minutes, leaving out one so close to the right edge
    /// that its label would be cut off.
    private var timeMarks: [Date] {
        guard let first = model.history.first?.time, let last = model.history.last?.time else { return [] }
        let step: TimeInterval = 600
        var t = (first.timeIntervalSinceReferenceDate / step).rounded(.up) * step
        var marks = [Date]()
        while t <= last.timeIntervalSinceReferenceDate - step / 2 {
            marks.append(Date(timeIntervalSinceReferenceDate: t))
            t += step
        }
        return marks
    }

    // MARK: Activity

    private var activity: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Recent activity").font(.headline)
                Spacer()
                Button("Show All") { model.page = .log }
                    .buttonStyle(.link)
            }
            if model.log.isEmpty {
                Text("Nothing yet.").foregroundStyle(.secondary)
            } else {
                ForEach(model.log.suffix(6)) { line in
                    Text(line.text)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(LogView.color(for: line.text))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 16))
    }

}

/// What the pool reports about your address, from its public API.
struct PoolAccountSection: View {
    let pool: String
    let website: URL?
    let account: PoolAccount?
    let updated: Date?
    let error: String?
    /// E.g. "mining now" or "you're not mining here now".
    var role: String?
    /// For a pool you aren't mining with: when it was last asked, and a way to ask
    /// again (it isn't refreshed on its own).
    var checked: Date?
    var checkNow: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("At \(pool)").font(.headline)
                if let role = role { Text(role).foregroundStyle(.secondary) }
                if let updated = updated {
                    Text("· updated \(updated, style: .relative) ago").foregroundStyle(.secondary)
                }
                if let checked = checked {
                    Text("· last checked \(checked.formatted(date: .abbreviated, time: .shortened))").foregroundStyle(.secondary)
                }
                Spacer()
                if let checkNow = checkNow { Button("Check Now", action: checkNow).controlSize(.small) }
                if let website = website { Link("Open Pool Page", destination: website) }
            }
            if let error = error {
                Text(error).font(.callout).foregroundStyle(.orange)
            } else if let a = account {
                if a.unknown {
                    Text("\(pool) hasn't recorded work from your address yet. It appears after the pool accepts your first share.")
                        .foregroundStyle(.secondary)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], alignment: .leading, spacing: 10) {
                        ForEach(Self.rows(a), id: \.0) { label, value in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(label).font(.caption).foregroundStyle(.secondary)
                                Text(value).font(.callout.weight(.medium)).monospacedDigit()
                            }
                        }
                    }
                    if let notice = a.notice {
                        Text(notice).font(.callout).foregroundStyle(.orange)
                    }
                }
            } else {
                Text("Asking \(pool) about your address…").foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 16))
    }

    /// A share of the pool's window; tiny shares read "under 0.0001%", not "0.0000%".
    static func percent(_ w: Double) -> String {
        w > 0 && w < 0.0001 ? "under 0.0001%" : String(format: w < 0.01 ? "%.4f%%" : "%.2f%%", w)
    }

    /// The fields this pool reports, in words.
    static func rows(_ a: PoolAccount) -> [(String, String)] {
        let btc = formatAmount
        var rows = [(String, String)]()
        if let online = a.online { rows.append(("Status", online ? "Online" : "No recent shares")) }
        if let h = a.hashrate, h > 0 { rows.append(("Hashrate it sees", formatHashrate(h))) }
        if let n = a.shares {
            rows.append(("Shares \(a.sharesPeriod ?? "")", "\(n) accepted" + ((a.rejected ?? 0) > 0 ? ", \(a.rejected!) rejected" : "")))
        }
        if let w = a.windowPercent { rows.append(("Your share of the window", percent(w))) }
        if let v = a.nextBlockPayout { rows.append(("If the pool found a block now", btc(v))) }
        if let v = a.perDay { rows.append(("Estimate per day", btc(v))) }
        if let v = a.unpaid { rows.append(("Unpaid", btc(v))) }
        if let v = a.immature { rows.append(("Waiting for maturity", btc(v))) }
        if let v = a.carried, v > 0 {
            rows.append(("Owed, below the payout minimum", btc(v) + (a.minimumPayout.map { " (paid from \(btc($0)))" } ?? "")))
        }
        if let v = a.paid { rows.append(("Paid", btc(v))) }
        if let v = a.earned { rows.append(("Earned in total", btc(v))) }
        return rows
    }
}
