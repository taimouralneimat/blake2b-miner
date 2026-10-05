import AppKit
import MinerCore
import SwiftUI

/// Shown on settings pages while changes are waiting for mining to restart.
struct RestartBanner: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        if model.hasPendingChanges {
            HStack {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .foregroundStyle(.tint)
                Text("Changes apply when mining restarts.")
                Spacer()
                Button("Restart Now") { model.applySettings() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
            .font(.callout)
            .padding(10)
            .background(.tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
        }
    }
}

/// The differentiator shown everywhere: who builds the blocks.
struct BuilderBadge: View {
    let youBuild: Bool
    var compact = false

    var body: some View {
        Label(youBuild ? (compact ? "You build" : "You build the blocks") : (compact ? "Pool builds" : "The pool builds the blocks"),
              systemImage: youBuild ? "checkmark.shield.fill" : "exclamationmark.triangle.fill")
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 7).padding(.vertical, 2)
            .foregroundStyle(youBuild ? Color.green : Color.orange)
            .background((youBuild ? Color.green : Color.orange).opacity(0.14), in: Capsule())
            .help(youBuild ? "Your own node chooses the transactions and builds the blocks you mine."
                           : "The pool's node chooses the transactions in the blocks you mine.")
    }
}

/// A caption under a form section.
struct SectionNote: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A one-line check result: the ✅ ⚠️ ❌ ℹ️ lines from NodeCheck and StratumProbe.
struct CheckLine: View {
    let text: String

    var body: some View {
        let (icon, tint, message) = Self.parse(text)
        Label {
            Text(message).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: icon).foregroundStyle(tint)
        }
        .font(.callout)
    }

    static func parse(_ text: String) -> (String, Color, String) {
        let markers: [(String, String, Color)] = [
            ("✅", "checkmark.circle.fill", .green), ("⚠️", "exclamationmark.triangle.fill", .orange),
            ("❌", "xmark.octagon.fill", .red), ("ℹ️", "info.circle.fill", .secondary),
        ]
        for (marker, icon, tint) in markers where text.hasPrefix(marker) {
            return (icon, tint, String(text.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces))
        }
        return ("circle", .secondary, text)
    }
}

extension MinerStatus {
    /// Under the share count: "accepted by the pool", rejected shares, and solo
    /// shares (found while a DATUM pool was reconnecting; never sent to it).
    var shareSummary: String {
        var parts = [sharesRejected > 0 ? "\(sharesRejected) rejected" : "accepted by the pool"]
        if soloSharesAccepted > 0 { parts.append("+\(soloSharesAccepted) solo") }
        return parts.joined(separator: " · ")
    }
}

/// A pool's fee, with a link to its website. A fee that's only "See website"
/// becomes the link itself.
struct FeeRow: View {
    let fee: String
    let website: URL?

    var body: some View {
        LabeledContent("Fee") {
            if let url = website, fee == "See website" {
                Link(fee, destination: url)
            } else {
                HStack(spacing: 8) {
                    Text(fee)
                    if let url = website { Link("Website", destination: url) }
                }
            }
        }
    }
}
