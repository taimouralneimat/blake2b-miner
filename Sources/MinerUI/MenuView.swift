import MinerCore
import SwiftUI

/// The menu-bar popover: status at a glance, start/stop, and the way to everything else.
public struct MenuView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if CPUInfo.isTranslated {
                Callout(icon: "exclamationmark.triangle.fill", tint: .orange, text: CPUInfo.rosettaWarning)
            }
            content
            primaryButton
            Divider()
            footer
        }
        .padding(16)
        .frame(width: 320)
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "cube.fill")
                    .font(.title3)
                    .foregroundStyle(.tint)
                Text("BLAKE2b Miner").font(.headline)
                Spacer()
                StatePill(state: model.isRunning ? model.status.state : .stopped)
            }
            HStack(spacing: 6) {
                Text(modeLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 4)
                BuilderBadge(youBuild: model.config.mode.youBuildTheBlocks, compact: true)
            }
        }
    }

    /// Mode and pool in a few words; the badge says who builds the blocks.
    private var modeLine: String {
        switch model.config.mode {
        case .datum:
            let pool = DatumPool.find(model.config.gateway.poolID)?.name
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
            Text("Uses \(model.config.threads) of \(CPUInfo.cores) CPU cores\(model.config.pauseOnBattery ? ", pauses on battery" : "").")
                .font(.callout)
                .foregroundStyle(.secondary)
            let found = model.foundBlocks.filter(\.isAccepted).count
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
                Button("Show Log") { show("log") }
                Button("Run Checks") { show("settings", tab: .diagnostics) }
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
            HStack(spacing: 8) {
                if s.mode == .solo {
                    StatTile(title: "Height", value: s.height.map { $0.formatted() } ?? "–",
                             detail: s.transactions.map { "\($0) transactions" })
                    StatTile(title: "Expected block", value: s.expectedSecondsPerBlock.map { "≈ " + formatDuration($0) } ?? "–",
                             detail: s.networkDifficulty.map { "difficulty " + $0.formatted(.number.notation(.compactName).precision(.significantDigits(3))) })
                } else {
                    StatTile(title: "Shares", value: "\(s.sharesAccepted)",
                             detail: s.sharesRejected > 0 ? "\(s.sharesRejected) rejected" : "accepted",
                             detailTint: s.sharesRejected > 0 ? .orange : nil)
                    StatTile(title: "Next share", value: s.expectedSecondsPerShare.map { "≈ " + formatDuration($0) } ?? "–",
                             detail: s.shareDifficulty.map { "difficulty " + $0.formatted() })
                }
            }
            if s.blocksFound > 0 {
                Label("\(s.blocksFound) block\(s.blocksFound == 1 ? "" : "s") found this session", systemImage: "star.fill")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.green)
            }
            HStack(spacing: 4) {
                Text("\(s.threads) threads")
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
            Button { show("settings", tab: .general) } label: {
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

    private var footer: some View {
        HStack(spacing: 2) {
            FooterButton(title: "Settings", icon: "gearshape") { show("settings") }
            FooterButton(title: "Log", icon: "text.alignleft") { show("log") }
            Spacer()
            FooterButton(title: "Quit", icon: "power") { NSApp.terminate(nil) }
        }
    }

    private func show(_ id: String, tab: SettingsTab? = nil) {
        if let tab = tab { model.settingsTab = tab }
        openWindow(id: id)
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

/// An icon-and-label button for the popover's bottom bar.
struct FooterButton: View {
    let title: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.callout)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .help(title)
    }
}

/// Whether a gateway status line reports a problem.
enum GatewayHint {
    case ok, problem

    static func from(_ status: String?) -> GatewayHint {
        status?.hasPrefix("Pool problem") == true ? .problem : .ok
    }
}
