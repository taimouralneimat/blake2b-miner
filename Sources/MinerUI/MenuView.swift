import MinerCore
import SwiftUI

/// The menu-bar popover: status at a glance, start/stop, and the way to everything else.
public struct MenuView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                header
                if CPUInfo.isTranslated {
                    Callout(icon: "exclamationmark.triangle.fill", tint: .orange, text: CPUInfo.rosettaWarning)
                }
                content
                primaryButton
                UpdateBanner(updater: model.updater, compact: true)
            }
            .padding(16)
            Divider()
            VStack(spacing: 0) {
                MenuRow(title: "Open Dashboard", icon: "macwindow", shortcut: "d") { show(.overview) }
                MenuRow(title: "Settings…", icon: "gearshape", shortcut: ",") { show(.mining) }
                Divider().padding(.vertical, 4).padding(.horizontal, 10)
                MenuRow(title: "Quit BLAKE2b Miner", icon: "power", shortcut: "q") { NSApp.terminate(nil) }
            }
            .padding(5)
        }
        .frame(width: 320)
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("BLAKE2b Miner").font(.headline)
                Spacer()
                StatePill(state: model.isRunning ? model.status.state : .stopped)
            }
            HStack(spacing: 6) {
                BuilderBadge(youBuild: model.config.mode.youBuildTheBlocks, compact: true)
                Text(modeLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    /// Mode and pool in a few words; the badge says who builds the blocks.
    private var modeLine: String {
        switch model.config.mode {
        case .datum:
            let pool = model.config.gateway.pool?.name
            return "Own DATUM Gateway · " + (pool ?? "solo")
        case .solo:
            return "Solo · your Knots node"
        case .stratum:
            return "Pool-hosted · " + (HostedGateway.find(url: model.config.stratum.url)?.name ?? model.config.stratum.url)
        }
    }

    // MARK: Content by state

    @ViewBuilder private var content: some View {
        if !model.isConfigured {
            welcome
        } else if !model.isRunning {
            ready
        } else if case .waiting(let reason) = model.status.state {
            waiting(reason)
        } else {
            mining
        }
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Welcome!").font(.title3.weight(.semibold))
            Text("Two steps to start: enter a payout address from your wallet, and check that Bitcoin Knots is running with its RPC server on.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var ready: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Ready to mine").font(.title3.weight(.semibold))
            Text("Mines with \(model.config.hardwareDescription)\(model.config.pauseOnBattery ? ", pauses on battery" : "").")
                .font(.callout)
                .foregroundStyle(.secondary)
            let found = model.foundBlocks.filter(\.countsAsFound).count
            if found > 0 {
                Label("\(found) block\(found == 1 ? "" : "s") found so far", systemImage: "star.fill")
                    .font(.callout)
                    .foregroundStyle(.green)
            }
        }
    }

    private func waiting(_ reason: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Callout(icon: "pause.circle.fill", tint: .orange, text: reason)
            HStack {
                Button("Show Log") { show(.log) }
                Button("Run Checks") { show(.diagnostics) }
                Spacer()
            }
            .controlSize(.small)
        }
    }

    private var mining: some View {
        let s = model.status
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(formatHashrate(s.hashrate))
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text("average").font(.caption2).foregroundStyle(.secondary)
                    Text(formatHashrate(s.averageHashrate)).font(.caption).monospacedDigit()
                }
            }
            if let g = s.gatewayStatus, case .problem = GatewayHint.from(g) {
                Callout(icon: "exclamationmark.triangle.fill", tint: .orange, text: g)
            }
            if s.poolRejectsEverything {
                Callout(icon: "xmark.octagon.fill", tint: .orange, text: s.poolRejectionWarning)
            }
            HStack(spacing: 8) {
                if s.mode == .solo {
                    StatTile(title: "Height", value: s.height.map { $0.formatted() } ?? "–",
                             detail: s.transactions.map { "\($0) transactions" })
                    StatTile(title: "Expected block", value: s.expectedSecondsPerBlock.map { "≈ " + formatDuration($0) } ?? "–",
                             detail: s.networkDifficulty.map { "difficulty " + $0.formatted(.number.notation(.compactName).precision(.significantDigits(3))) })
                } else {
                    StatTile(title: "Shares", value: "\(s.confirmedShares)",
                             detail: s.shareSummary,
                             detailTint: s.sharesRejected > 0 || s.poolRejected > 0 ? .orange : nil)
                    StatTile(title: "Next share", value: s.expectedSecondsPerShare.map { "≈ " + formatDuration($0) } ?? "–",
                             detail: s.shareDifficulty.map { "difficulty " + formatDifficulty($0) })
                }
            }
            if s.blocksFound > 0 {
                Label("\(s.blocksFound) block\(s.blocksFound == 1 ? "" : "s") found this session", systemImage: "star.fill")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.green)
            }
            HStack(spacing: 4) {
                Text(s.speedSplit ?? "\(s.threads) threads")
                if let start = s.startedAt {
                    Text("·")
                    Text("running \(start, style: .relative)")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: Actions

    @ViewBuilder private var primaryButton: some View {
        if !model.isConfigured {
            Button { show(.mining) } label: {
                Label("Set Up…", systemImage: "gearshape").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        } else if model.isRunning {
            Button { model.stop() } label: {
                Label("Stop Mining", systemImage: "stop.fill").frame(maxWidth: .infinity)
            }
            .controlSize(.large)
        } else {
            Button { model.start() } label: {
                Label("Start Mining", systemImage: "play.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
    }

    private func show(_ page: Page) {
        model.page = page
        openWindow(id: MainWindowView.id)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - Building blocks

/// Small capsule showing the miner's state.
struct StatePill: View {
    let state: MinerState

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(title).font(.caption.weight(.medium))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(color.opacity(0.14), in: Capsule())
    }

    private var title: String {
        switch state {
        case .mining: return "Mining"
        case .starting: return "Starting"
        case .waiting: return "Waiting"
        case .stopped: return "Stopped"
        }
    }

    private var color: Color {
        switch state {
        case .mining: return .green
        case .starting: return .yellow
        case .waiting: return .orange
        case .stopped: return .secondary
        }
    }
}

/// One number with a caption, in a rounded tile.
struct StatTile: View {
    let title: String
    let value: String
    var detail: String?
    var detailTint: Color?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let detail = detail {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(detailTint ?? .secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
    }
}

/// A tinted box with an icon and a message (problems, warnings).
struct Callout: View {
    let icon: String
    let tint: Color
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon).foregroundStyle(tint)
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }
}

/// A row that looks and behaves like a native menu item: it highlights on
/// hover and shows its keyboard shortcut.
struct MenuRow: View {
    let title: String
    let icon: String
    let shortcut: Character
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .frame(width: 16)
                Text(title)
                Spacer()
                Text("⌘\(String(shortcut).uppercased())")
                    .foregroundStyle(hovering ? Color.white.opacity(0.8) : Color.secondary)
            }
            .font(.body)
            .foregroundStyle(hovering ? Color.white : Color.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(hovering ? Color.accentColor : .clear, in: RoundedRectangle(cornerRadius: 5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(KeyEquivalent(shortcut), modifiers: .command)
        .onHover { hovering = $0 }
    }
}

/// Whether a gateway status line reports a problem.
enum GatewayHint {
    case ok, problem

    static func from(_ status: String?) -> GatewayHint {
        status?.hasPrefix("Pool problem") == true ? .problem : .ok
    }

}
