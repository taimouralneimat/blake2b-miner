import MinerCore
import SwiftUI

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
                if let url = pool.websiteURL { Link("About \(pool.name)", destination: url).font(.callout) }
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

struct StratumSettings: View {
    @EnvironmentObject var model: AppModel
    @State private var probe: [String] = []
    @State private var probing = false

    private var preset: HostedGateway? { HostedGateway.find(url: model.config.stratum.url) }

    var body: some View {
        Section {
            Picker("Pool", selection: Binding(
                get: { preset?.id ?? "custom" },
                set: { id in
                    if let p = HostedGateway.all.first(where: { $0.id == id }) {
                        model.config.stratum.url = p.url
                        if model.config.stratum.user.isEmpty { model.config.stratum.user = model.config.payoutAddress }
                    } else if preset != nil {
                        model.config.stratum.url = "127.0.0.1:23334"
                    }
                    probe = []
                })) {
                ForEach(HostedGateway.all) { Text($0.name).tag($0.id) }
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
                if let p = preset, let url = p.websiteURL { Link("About \(p.name)", destination: url) }
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
