import AppKit
import MinerCore
import SwiftUI

/// How to reach the Bitcoin Knots node.
struct NodeSettingsView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Form {
            Section {
                TextField("Address", text: $model.config.node.host, prompt: Text("127.0.0.1"))
                TextField("RPC port", value: $model.config.node.port, format: .number.grouping(.never))
                LabeledContent("Data directory") {
                    VStack(alignment: .trailing, spacing: 6) {
                        Text(abbreviated(model.config.node.resolvedDataDir))
                            .font(.callout.monospaced())
                            .lineLimit(1)
                            .truncationMode(.head)
                            .help(model.config.node.resolvedDataDir)
                        HStack(spacing: 8) {
                            if !model.config.node.dataDir.isEmpty {
                                Button("Use Default") { model.config.node.dataDir = "" }
                            }
                            Button("Choose…") { chooseDataDir() }
                        }
                        .controlSize(.small)
                    }
                }
            } header: {
                Text("Bitcoin Knots node")
            } footer: {
                SectionNote("Every mode except pool-hosted gateways uses your node. Turn on its RPC server: server=1 in bitcoin.conf, or Bitcoin Knots › Settings › Options › Enable RPC server. The miner signs in with the node's cookie file from the data directory.")
            }
            Section {
                TextField("RPC user", text: $model.config.node.rpcUser)
                SecureField("RPC password", text: $model.config.node.rpcPassword)
            } header: {
                Text("RPC user and password (optional)")
            } footer: {
                SectionNote("Only needed if your node uses rpcuser/rpcpassword or rpcauth instead of the cookie. The password is kept in your Keychain.")
            }
            if !model.config.node.isLocal {
                Section {
                    Label("RPC to another computer is unencrypted. Use it only on a network you trust, or through an SSH tunnel.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
            }
            RestartBanner()
        }
        .formStyle(.grouped)
    }

    private func abbreviated(_ path: String) -> String {
        (path as NSString).abbreviatingWithTildeInPath
    }

    private func chooseDataDir() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.showsHiddenFiles = true
        panel.message = "Choose Bitcoin Knots' data directory (the folder containing .cookie)"
        panel.directoryURL = URL(fileURLWithPath: model.config.node.resolvedDataDir)
        if panel.runModal() == .OK, let url = panel.url { model.config.node.dataDir = url.path }
    }
}
