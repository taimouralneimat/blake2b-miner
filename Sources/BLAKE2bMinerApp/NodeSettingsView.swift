import AppKit
import MinerCore
import SwiftUI

struct NodeSettings: View {
    @EnvironmentObject var model: AppModel
    @State private var initial = MinerConfig()

    var body: some View {
        Form {
            Section {
                TextField("RPC host", text: $model.config.node.host)
                TextField("RPC port", value: $model.config.node.port, format: .number.grouping(.never))
                HStack {
                    TextField("Data directory", text: $model.config.node.dataDir, prompt: Text(NodeConfig.defaultDataDir))
                    Button("Choose…") { chooseDataDir() }
                }
            } header: {
                Text("Bitcoin Knots node")
            } footer: {
                Text("Used for solo mining. Bitcoin Knots must run with server=1 (in bitcoin.conf or Settings › Options › Enable RPC server). The miner signs in with the node's cookie file from the data directory.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                TextField("RPC user", text: $model.config.node.rpcUser)
                SecureField("RPC password", text: $model.config.node.rpcPassword)
            } header: {
                Text("Optional: RPC user and password")
            } footer: {
                Text("Only needed if your node is set up with rpcuser/rpcpassword or rpcauth instead of the cookie.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            RestartBanner(initial: initial)
        }
        .formStyle(.grouped)
        .onAppear { initial = model.config }
    }

    private func chooseDataDir() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.showsHiddenFiles = true
        panel.directoryURL = URL(fileURLWithPath: model.config.node.resolvedDataDir)
        if panel.runModal() == .OK, let url = panel.url { model.config.node.dataDir = url.path }
    }
}
