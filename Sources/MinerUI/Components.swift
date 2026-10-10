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
    /// Under the share count (which counts what the pool itself accepted): shares
    /// waiting for or rejected by the pool, and solo shares (found while a DATUM
    /// pool was reconnecting; never sent to it).
    var shareSummary: String {
        let pool = poolName ?? "the pool"
        var parts = [String]()
        if poolPending > 0 && poolName != nil { parts.append("\(poolPending) waiting for \(pool)") }
        if poolRejected > 0 { parts.append("\(poolRejected) rejected by \(pool)") }
        if sharesRejected > 0 { parts.append("\(sharesRejected) rejected") }
        if parts.isEmpty { parts.append("accepted by \(pool)") }
        if soloSharesAccepted > 0 { parts.append("+\(soloSharesAccepted) solo") }
        return parts.joined(separator: " · ")
    }

    /// The pool rejects your shares and has accepted none: worth a warning.
    var poolRejectsEverything: Bool { poolRejected > 0 && poolConfirmed == 0 }

    /// The warning text for `poolRejectsEverything`.
    var poolRejectionWarning: String {
        let pool = poolName ?? "The pool"
        return "\(pool) rejected your shares (\(poolRejectReason ?? "no reason given")) and hasn't accepted any. Your gateway and node are working; try another DATUM pool in Mining settings."
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

extension MinerStatus {
    /// "CPU 318 MH/s · GPU 712 MH/s" while the GPU mines; nil for CPU-only mining.
    var speedSplit: String? {
        guard gpuName != nil else { return nil }
        return threads > 0 ? "CPU \(formatHashrate(cpuHashrate)) · GPU \(formatHashrate(gpuHashrate))"
                           : "GPU \(formatHashrate(gpuHashrate))"
    }
}
