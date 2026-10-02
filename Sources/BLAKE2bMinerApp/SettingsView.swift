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

struct MiningSettings: View {
    @EnvironmentObject var model: AppModel
    @State private var initial = MinerConfig()

    var body: some View {
        Form {
            Picker("Mode", selection: $model.config.mode) {
                Text("Solo with my Knots node").tag(MiningMode.solo)
                Text("Pool or DATUM Gateway (Stratum)").tag(MiningMode.stratum)
            }
            .pickerStyle(.radioGroup)

            if model.config.mode == .solo {
                Section {
                    TextField("Payout address", text: $model.config.payoutAddress, prompt: Text("bc1… or 1…"))
                        .font(.body.monospaced())
                    TextField("Coinbase text", text: $model.config.coinbaseTag)
                } footer: {
                    Text("Blocks you find pay the full reward to this address. Use an address from your own wallet. Check it with Verify › Test Node Connection.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                StratumSettings()
            }

            Section("CPU") {
                Stepper(value: $model.config.threads, in: 1...CPUInfo.cores) {
                    Text("Threads: \(model.config.threads) of \(CPUInfo.cores)")
                        .monospacedDigit()
                }
                Toggle("Keep the Mac responsive (lower priority)", isOn: $model.config.lowPriority)
                Toggle("Pause while on battery power", isOn: $model.config.pauseOnBattery)
                Toggle("Prevent the Mac from sleeping while mining", isOn: $model.config.preventSleep)
            }

            Section("App") {
                Toggle("Open at login", isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
                Toggle("Start mining when the app opens", isOn: $model.prefs.startMiningAtLaunch)
                Toggle("Show hashrate in the menu bar", isOn: $model.prefs.showHashrateInMenuBar)
            }
            RestartBanner(initial: initial)
        }
        .formStyle(.grouped)
        .onAppear { initial = model.config }
    }
}

struct StratumSettings: View {
    @EnvironmentObject var model: AppModel
    @State private var probe: [String] = []
    @State private var probing = false

    private var preset: PoolPreset? { PoolPreset.all.first { $0.url == model.config.stratum.url } }

    var body: some View {
        Section {
            Picker("Pool", selection: Binding(
                get: { preset?.id ?? "custom" },
                set: { id in
                    if let p = PoolPreset.all.first(where: { $0.id == id }) {
                        model.config.stratum.url = p.url
                        if model.config.stratum.user.isEmpty { model.config.stratum.user = model.config.payoutAddress }
                    } else if preset != nil {
                        model.config.stratum.url = "127.0.0.1:23334"
                    }
                    probe = []
                })) {
                ForEach(PoolPreset.all) { Text($0.name).tag($0.id) }
                Divider()
                Text("My own DATUM Gateway / custom").tag("custom")
            }
            TextField("Server", text: $model.config.stratum.url, prompt: Text("127.0.0.1:23334"))
                .disabled(preset != nil)
            TextField("Username", text: $model.config.stratum.user, prompt: Text("your payout address, optionally .workername"))
                .font(.body.monospaced())
            TextField("Password", text: $model.config.stratum.password)
            HStack {
                Button(probing ? "Testing…" : "Test Server") { runProbe() }
                    .disabled(probing || model.config.stratum.url.isEmpty)
                if let p = preset { Link("About \(p.name)", destination: URL(string: p.website)!) }
            }
            ForEach(probe, id: \.self) { Text($0).font(.callout).textSelection(.enabled) }
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                if let p = preset {
                    Text("\(p.note) Fee: \(p.fee).")
                }
                Text("Pools pay by shares, and they set the share difficulty for ASICs: at CPU speed a share can take days, so expect tiny, rare payouts. Any block you find still counts in full for the pool.")
                Text("Running your own DATUM Gateway (github.com/CONVOYMining/datum_gateway) next to your Knots node lets you build your own blocks and set a lower share difficulty. Choose \"My own DATUM Gateway\" and enter its address (port 23334 by default).")
            }
            .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func runProbe() {
        probing = true
        probe = []
        let config = model.config.stratum
        Task.detached {
            let report = StratumProbe.run(config)
            await MainActor.run {
                probe = report.lines + [report.compatible ? "✅ This server works with BLAKE2b Miner." : "❌ This server can't be used as configured."]
                probing = false
            }
        }
    }
}

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

struct VerifyView: View {
    @EnvironmentObject var model: AppModel
    @State private var nodeReport: [String] = []
    @State private var testResults: [SelfTest.Result] = []
    @State private var busy = false

    var body: some View {
        Form {
            Section {
                Button("Test Node Connection") { testNode() }.disabled(busy)
                ForEach(nodeReport, id: \.self) { Text($0).font(.callout).textSelection(.enabled) }
            } footer: {
                Text("Checks that the node is reachable, synced and on the BLAKE2b chain, and that your payout address is valid and belongs to one of the node's wallets.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Button("Run Self-Test") { selfTest() }.disabled(busy)
                ForEach(testResults, id: \.name) { r in
                    Label {
                        VStack(alignment: .leading) {
                            Text(r.name)
                            Text(r.detail).font(.caption).foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: r.passed ? "checkmark.circle.fill" : "xmark.octagon.fill")
                            .foregroundStyle(r.passed ? .green : .red)
                    }
                }
            } footer: {
                Text("Verifies the hashing against the official Bitcoin Knots header-v2 test vectors and against recent blocks from your node.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if busy { ProgressView().frame(maxWidth: .infinity) }
        }
        .formStyle(.grouped)
    }

    private func testNode() {
        busy = true
        nodeReport = []
        let config = model.config
        Task.detached {
            let lines = NodeCheck.run(config)
            await MainActor.run {
                nodeReport = lines
                busy = false
            }
        }
    }

    private func selfTest() {
        busy = true
        testResults = []
        let node = model.config.node
        Task.detached {
            let results = SelfTest.run(node: node)
            await MainActor.run {
                testResults = results
                busy = false
            }
        }
    }
}

struct AboutView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "cube.fill").font(.system(size: 44)).foregroundStyle(.tint)
            Text("BLAKE2b Miner").font(.title2.bold())
            Text("Version \(Miner.version)").foregroundStyle(.secondary)
            Text("A CPU miner for the Bitcoin Knots BLAKE2b (header v2) chain. Solo mine with your own node, or connect to a DATUM Gateway.")
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            HStack {
                Button("Show Log File") { model.revealLogFile() }
                Button("Show Found Blocks") { model.revealFoundBlocks() }
            }
            Text("MIT License. No warranty: mining with a CPU is a lottery and most likely never finds a block.")
                .font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
    }
}

/// Human-readable checks of the node setup.
enum NodeCheck {
    static func run(_ config: MinerConfig) -> [String] {
        let rpc = NodeRPC(config.node, timeout: 10)
        var out = [String]()
        do {
            let info = try rpc.call("getblockchaininfo") as? [String: Any] ?? [:]
            let chain = info["chain"] as? String ?? "?"
            let blocks = info["blocks"] as? Int ?? 0
            out.append("✅ Connected: chain \"\(chain)\", height \(blocks.formatted())")
            if info["initialblockdownload"] as? Bool == true { out.append("⚠️ The node is still syncing; wait until it finishes.") }
            let networkInfo = try? rpc.call("getnetworkinfo") as? [String: Any]
            if let sub = networkInfo?["subversion"] as? String { out.append("ℹ️ Node software: \(sub)") }
            do {
                let t = try rpc.call("getblocktemplate", [["rules": ["segwit", "blake2b"]]]) as? [String: Any] ?? [:]
                let v = (t["version"] as? NSNumber)?.uint32Value ?? 0
                out.append(v & HeaderV2.versionFlag != 0
                           ? "✅ Templates are BLAKE2b (header v2) blocks"
                           : "❌ Templates are not BLAKE2b blocks. Is this the BLAKE2b chain?")
            } catch {
                out.append("❌ getblocktemplate failed: \(error.localizedDescription)")
            }
            let address = config.payoutAddress.trimmingCharacters(in: .whitespaces)
            if address.isEmpty {
                out.append("⚠️ No payout address set")
            } else {
                let v = try rpc.call("validateaddress", [address]) as? [String: Any] ?? [:]
                guard v["isvalid"] as? Bool == true else {
                    out.append("❌ \(address) is not a valid address on this chain")
                    return out
                }
                out.append("✅ Payout address is valid")
                let wallets = (try? rpc.call("listwallets") as? [String]) ?? []
                let owner = wallets.first { w in
                    ((try? rpc.call("getaddressinfo", [address], wallet: w) as? [String: Any])?["ismine"] as? Bool) == true
                }
                if let owner = owner {
                    out.append("✅ Address belongs to your wallet \"\(owner.isEmpty ? "(default)" : owner)\"")
                } else if wallets.isEmpty {
                    out.append("ℹ️ No wallet loaded in the node, so ownership of the address can't be checked")
                } else {
                    out.append("⚠️ The address is not in any wallet loaded in this node. Make sure you control it!")
                }
            }
        } catch {
            out.append("❌ \(error.localizedDescription)")
        }
        return out
    }
}
