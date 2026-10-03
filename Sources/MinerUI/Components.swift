import AppKit
import MinerCore
import SwiftUI

/// Shown at the bottom of a settings page when its changes are waiting for a restart.
struct RestartBanner: View {
    @EnvironmentObject var model: AppModel
    let initial: MinerConfig

    var body: some View {
        if model.isRunning && model.config != initial {
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
