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
            Section {
                Picker("How do you want to mine?", selection: $model.config.mode) {
                    ModeChoice(title: "My own DATUM Gateway (recommended)",
                               detail: "Your node builds the blocks. Pool through a DATUM pool, or mine solo.",
                               buildsBlocks: true).tag(MiningMode.datum)
                    ModeChoice(title: "Solo, directly with my node",
                               detail: "Your node builds the blocks; any block you find pays you in full.",
                               buildsBlocks: true).tag(MiningMode.solo)
                    ModeChoice(title: "Pool-hosted gateway",
                               detail: "Simplest, but the pool chooses the transactions: less decentralized.",
                               buildsBlocks: false).tag(MiningMode.stratum)
                }
                .pickerStyle(.radioGroup)
            }

            if model.config.mode != .stratum {
                Section {
                    TextField("Payout address", text: $model.config.payoutAddress, prompt: Text("bc1… or 1…"))
                        .font(.body.monospaced())
                    if model.config.mode == .solo {
                        TextField("Coinbase text", text: $model.config.coinbaseTag)
                    }
                } footer: {
                    Text(model.config.mode == .datum
                         ? "Your pool payouts, and any block mined solo, go to this address. Use an address from your own wallet."
                         : "Blocks you find pay the full reward to this address. Use an address from your own wallet.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            switch model.config.mode {
            case .datum: GatewaySettingsView()
            case .stratum: StratumSettings()
            case .solo: EmptyView()
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

struct GatewaySettingsView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Section {
            Picker("DATUM pool", selection: $model.config.gateway.poolID) {
                ForEach(DatumPool.all) { Text("\($0.name) · fee \($0.fee)").tag($0.id) }
                Divider()
                Text("None: solo through my gateway").tag("")
            }
            if let pool = DatumPool.find(model.config.gateway.poolID) {
                Toggle("If \(pool.name) is unreachable, keep mining solo", isOn: $model.config.gateway.soloWhenPoolDown)
                Link("About \(pool.name)", destination: URL(string: pool.website)!).font(.callout)
            }
        } header: {
            Text("DATUM")
        } footer: {
            Text("The app runs the DATUM Gateway for you, next to your Bitcoin Knots node. Your node chooses the transactions and builds every block; the DATUM pool only coordinates who gets paid, straight from the coinbase. The pool sets the minimum share difficulty.")
                .font(.caption).foregroundStyle(.secondary)
        }
        Section {
            TextField("Stratum port", value: $model.config.gateway.stratumPort, format: .number.grouping(.never))
            Toggle("Let other miners on my network use this gateway", isOn: $model.config.gateway.allowNetworkMiners)
            if model.config.gateway.allowNetworkMiners {
                Text("ASICs and other computers can connect to stratum+tcp://\(LocalNetwork.address ?? "this-mac"):\(model.config.gateway.stratumPort) with your payout address as the username.")
                    .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
        } header: {
            Text("Gateway")
        } footer: {
            Text("For pooled DATUM mining, Bitcoin Knots needs room in each block for the pool's payouts: add blockmaxweight=785000 to bitcoin.conf (Verify › Test Node Connection checks this).")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

enum LocalNetwork {
    /// The Mac's primary IPv4 address on the local network.
    static var address: String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }
        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let ifa = ptr.pointee
            guard let addr = ifa.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET),
                  String(cString: ifa.ifa_name).hasPrefix("en") else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                return String(cString: host)
            }
        }
        return nil
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
                Text("Custom server").tag("custom")
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
                Text("With a pool-hosted gateway the pool's node chooses the transactions in the blocks you mine. To build your own blocks, use \"My own DATUM Gateway\" instead. Some pools plan to pay only miners who build their own blocks.")
                Text("Pools pay by shares and set the share difficulty for ASICs: at CPU speed a share can take days, so expect tiny, rare payouts.")
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
    /// blockmaxweight from the node's bitcoin.conf or its GUI settings.json, if set.
    static func blockMaxWeight(_ node: NodeConfig) -> Int? {
        let dir = URL(fileURLWithPath: node.resolvedDataDir)
        if let data = try? Data(contentsOf: dir.appendingPathComponent("settings.json")),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let v = json["blockmaxweight"] {
            if let n = v as? Int { return n }
            if let s = v as? String, let n = Int(s) { return n }
        }
        guard let conf = try? String(contentsOf: dir.appendingPathComponent("bitcoin.conf"), encoding: .utf8) else { return nil }
        var value: Int?
        for line in conf.split(separator: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("blockmaxweight="), let n = Int(t.dropFirst("blockmaxweight=".count)) { value = n }
            if t.hasPrefix("[") { break }  // network-specific sections follow; main section only
        }
        return value
    }

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
            if config.mode == .datum && !config.gateway.poolID.isEmpty {
                switch NodeCheck.blockMaxWeight(config.node) {
                case let w? where w <= 785_000:
                    out.append("✅ blockmaxweight=\(w) leaves room for DATUM pool payouts")
                case let w?:
                    out.append("⚠️ blockmaxweight=\(w) is too high for DATUM pooling; set blockmaxweight=785000 in bitcoin.conf and restart Knots")
                case nil:
                    out.append("⚠️ For DATUM pooling add blockmaxweight=785000 to bitcoin.conf (in \(config.node.resolvedDataDir)) and restart Knots, so blocks have room for the pool's payouts")
                }
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
