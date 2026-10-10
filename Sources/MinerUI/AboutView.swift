import AppKit
import MinerCore
import SwiftUI

struct AboutView: View {
    @EnvironmentObject var model: AppModel

    private static let repository = URL(string: "https://github.com/taimouralneimat/blake2b-miner")

    var body: some View {
        VStack(spacing: 14) {
            Spacer(minLength: 0)
            appIcon.frame(width: 96, height: 96)
            VStack(spacing: 4) {
                Text("BLAKE2b Miner").font(.title.weight(.semibold))
                Text("Version \(Miner.version)").foregroundStyle(.secondary)
            }
            Text("A CPU and GPU miner for the Bitcoin Knots BLAKE2b chain, built so that your own node builds the blocks you mine: with the bundled DATUM Gateway, or solo.")
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
            UpdateStatus(updater: model.updater)
            HStack(spacing: 10) {
                Button("Show Log File") { model.revealLogFile() }
                Button("Show Found Blocks") { model.revealFoundBlocks() }
            }
            HStack(spacing: 16) {
                if let repo = Self.repository {
                    Link("Website", destination: repo)
                    Link("Report an Issue", destination: repo.appendingPathComponent("issues"))
                }
                Button("Licenses") { openNotices() }
                    .buttonStyle(.link)
            }
            .font(.callout)
            Spacer(minLength: 0)
            Text("MIT License. Mining with a Mac is a lottery: it most likely never finds a block.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The app's icon; a stand-in symbol when not running from the app bundle.
    @ViewBuilder private var appIcon: some View {
        if Bundle.main.bundleIdentifier != nil, let icon = NSApp?.applicationIconImage {
            Image(nsImage: icon).resizable()
        } else {
            Image(systemName: "desktopcomputer").resizable().scaledToFit().foregroundStyle(.tint).padding(12)
        }
    }

    /// THIRD_PARTY_NOTICES.md ships in the app's Resources.
    private func openNotices() {
        if let url = Bundle.main.url(forResource: "THIRD_PARTY_NOTICES", withExtension: "md") {
            NSWorkspace.shared.open(url)
        } else if let repo = Self.repository {
            NSWorkspace.shared.open(repo.appendingPathComponent("blob/main/THIRD_PARTY_NOTICES.md"))
        }
    }
}

/// Check for Updates, and what the last check found.
private struct UpdateStatus: View {
    @ObservedObject var updater: Updater

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Button("Check for Updates") { updater.check(userInitiated: true) }
                    .disabled(updater.state == .checking)
                Toggle("Check automatically", isOn: $updater.automatic)
                    .toggleStyle(.checkbox)
            }
            switch updater.state {
            case .checking:
                ProgressView().controlSize(.small)
            case .upToDate:
                Text("You have the latest version.").font(.callout).foregroundStyle(.secondary)
            default:
                UpdateBanner(updater: updater).frame(maxWidth: 460)
            }
        }
    }
}
