import AppKit
import MinerCore
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        TabView {
            MiningSettings().tabItem { Label("Mining", systemImage: "cube") }
            NodeSettings().tabItem { Label("Node", systemImage: "server.rack") }
            VerifyView().tabItem { Label("Verify", systemImage: "checkmark.seal") }
            AboutView().tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 520)
        .padding(.bottom, 8)
    }
}

/// Shown when settings changed while mining.
struct RestartBanner: View {
    @EnvironmentObject var model: AppModel
    let initial: MinerConfig

    var body: some View {
        if model.isRunning && model.config != initial {
            HStack {
                Image(systemName: "arrow.triangle.2.circlepath")
                Text("Changes apply when mining restarts.")
                Spacer()
                Button("Restart Now") { model.applySettings() }
            }
            .font(.callout)
            .padding(8)
            .background(.yellow.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
        }
    }
}

/// The differentiator shown everywhere: who builds the blocks.
struct BuilderBadge: View {
    let youBuild: Bool

    var body: some View {
        Label(youBuild ? "You build the blocks" : "The pool builds the blocks",
              systemImage: youBuild ? "checkmark.shield.fill" : "exclamationmark.triangle.fill")
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 7).padding(.vertical, 2)
            .foregroundStyle(youBuild ? Color.green : Color.orange)
            .background((youBuild ? Color.green : Color.orange).opacity(0.14), in: Capsule())
    }
}

struct ModeChoice: View {
    let title: String
    let detail: String
    let buildsBlocks: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title)
                BuilderBadge(youBuild: buildsBlocks)
            }
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
