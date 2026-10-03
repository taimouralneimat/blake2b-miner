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
                chartCard
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 14)], spacing: 14) {
                    ForEach(cards, id: \.title) { card in
                        StatTile(title: card.title, value: card.value, detail: card.detail, detailTint: card.tint)
                    }
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
        case .datum: mode = "Own DATUM Gateway · " + (DatumPool.find(model.config.gateway.poolID).map { "pooled with \($0.name)" } ?? "solo")
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
                .chartXAxis { AxisMarks(values: .stride(by: .minute, count: 10)) { _ in AxisGridLine(); AxisValueLabel(format: .dateTime.hour().minute()) } }
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
            list.append(Card(title: "Shares", value: "\(s.sharesAccepted)",
                             detail: s.shareSummary,
                             tint: s.sharesRejected > 0 ? .orange : nil))
            list.append(Card(title: "Share difficulty", value: s.shareDifficulty.map(formatDifficulty) ?? "–", detail: "set by the pool"))
            if model.config.mode == .datum {
                list.append(Card(title: "Pool", value: DatumPool.find(model.config.gateway.poolID)?.name ?? "Solo",
                                 detail: poolState))
            }
        }
        let found = model.foundBlocks.filter(\.countsAsFound).count
        list.append(Card(title: "Blocks found", value: "\(found)", detail: found > 0 ? "all time" : "a CPU lottery ticket",
                         tint: found > 0 ? .green : nil))
        list.append(Card(title: "Threads", value: "\(model.isRunning ? s.threads : model.config.threads) of \(CPUInfo.cores)",
                         detail: model.config.lowPriority ? "low priority" : "full priority"))
        if let start = s.startedAt, model.isRunning {
            list.append(Card(title: "Running for", value: formatDuration(Date().timeIntervalSince(start)),
                             detail: "\(formatHashes(s.totalHashes)) hashes"))
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
        Double(n).formatted(.number.notation(.compactName).precision(.significantDigits(3)))
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
