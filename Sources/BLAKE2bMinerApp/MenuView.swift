import MinerCore
import SwiftUI

struct MenuView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            if model.isRunning {
                stats
            } else {
                idleHint
            }
            Divider()
            HStack {
                if model.isRunning {
                    Button(role: .destructive) { model.stop() } label: {
                        Label("Stop Mining", systemImage: "stop.fill").frame(maxWidth: .infinity)
                    }
                } else {
                    Button { model.start() } label: {
                        Label("Start Mining", systemImage: "play.fill").frame(maxWidth: .infinity)
                    }
                    .disabled(!model.isConfigured)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .controlSize(.large)
            HStack {
                Button("Settings…") { show("settings") }
                Button("Log") { show("log") }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
            .buttonStyle(.borderless)
        }
        .padding(14)
        .frame(width: 300)
    }

    private func show(_ id: String) {
        openWindow(id: id)
        NSApp.activate(ignoringOtherApps: true)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Circle().fill(stateColor).frame(width: 9, height: 9)
            VStack(alignment: .leading, spacing: 3) {
                Text(stateTitle).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                BuilderBadge(youBuild: model.config.mode != .stratum)
            }
            Spacer()
        }
    }

    private var stateColor: Color {
        switch model.status.state {
        case .mining: return .green
        case .starting: return .yellow
        case .waiting: return .orange
        case .stopped: return .secondary
        }
    }

    private var stateTitle: String {
        guard model.isRunning else { return "Not mining" }
        switch model.status.state {
        case .mining: return "Mining · " + formatHashrate(model.status.hashrate)
        case .starting: return "Starting…"
        case .waiting: return "Waiting"
        case .stopped: return "Stopping…"
        }
    }

    private var subtitle: String {
        if case .waiting(let reason) = model.status.state { return reason }
        switch model.config.mode {
        case .datum:
            if let g = model.status.gatewayStatus, model.isRunning { return g }
            let pool = DatumPool.find(model.config.gateway.poolID)?.name
            return "Own DATUM Gateway · " + (pool.map { "pooled with \($0)" } ?? "solo")
        case .solo: return "Solo mining · Knots node \(model.config.node.host):\(model.config.node.port)"
        case .stratum:
            let pool = PoolPreset.all.first { $0.url == model.config.stratum.url }?.name ?? model.config.stratum.url
            return "Pool-hosted gateway · \(pool)"
        }
    }

    @ViewBuilder private var stats: some View {
        let s = model.status
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 5) {
            row("Hashrate", formatHashrate(s.hashrate))
            row("Average", formatHashrate(s.averageHashrate))
            if s.mode == .solo {
                row("Height", s.height.map { $0.formatted() } ?? "–")
                row("Difficulty", s.networkDifficulty.map { $0.formatted(.number.notation(.compactName).precision(.significantDigits(3))) } ?? "–")
                row("Expected block", s.expectedSecondsPerBlock.map { "≈ " + formatDuration($0) } ?? "–")
                row("Blocks found", "\(s.blocksFound)")
            } else {
                row("Shares", "\(s.sharesAccepted) accepted · \(s.sharesRejected) rejected")
                row("Share difficulty", s.shareDifficulty.map { $0.formatted() } ?? "–")
                if let d = s.shareDifficulty, s.hashrate > 0 {
                    row("Expected share", "≈ " + formatDuration(d * 4_294_967_296 / s.hashrate))
                }
            }
            row("Threads", "\(s.threads) of \(CPUInfo.cores)")
            if let start = s.startedAt {
                GridRow {
                    Text("Running for").foregroundStyle(.secondary)
                    Text(start, style: .relative)
                }
            }
        }
        .font(.callout)
        .monospacedDigit()
    }

    private func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value).textSelection(.enabled)
        }
    }

    @ViewBuilder private var idleHint: some View {
        if !model.isConfigured {
            Text(model.config.mode == .stratum
                 ? "Set the Stratum server and username in Settings."
                 : "Set your payout address in Settings to start mining.")
                .font(.callout).foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text("Ready to mine with \(model.config.threads) of \(CPUInfo.cores) CPU cores.")
                if !model.foundBlocks.isEmpty {
                    Text("Blocks found so far: \(model.foundBlocks.filter { $0.result == "accepted" }.count)")
                }
            }
            .font(.callout).foregroundStyle(.secondary)
        }
    }
}
