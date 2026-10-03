import MinerCore
import SwiftUI

/// How to mine, where payouts go, and which pool.
struct GeneralSettingsView: View {
    @EnvironmentObject var model: AppModel
    @State private var initial = MinerConfig()

    var body: some View {
        Form {
            Section {
                Picker("How do you want to mine?", selection: $model.config.mode) {
                    ModeChoice(title: "My own DATUM Gateway", recommended: true,
                               detail: "Pool through a DATUM pool, or mine solo, while your node builds the blocks.",
                               buildsBlocks: true).tag(MiningMode.datum)
                    ModeChoice(title: "Solo, directly with my node",
                               detail: "Any block you find pays the full reward to you.",
                               buildsBlocks: true).tag(MiningMode.solo)
                    ModeChoice(title: "Pool-hosted gateway",
                               detail: "Simplest, but the pool chooses the transactions: less decentralized.",
                               buildsBlocks: false).tag(MiningMode.stratum)
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
            } header: {
                Text("How do you want to mine?")
            }

            if model.config.mode != .stratum {
                Section {
                    AddressField(label: "Payout address", text: $model.config.payoutAddress)
                    if model.config.mode == .solo {
                        TextField("Coinbase text", text: $model.config.coinbaseTag, prompt: Text("/BLAKE2b Miner/"))
                    }
                } footer: {
                    SectionNote(model.config.mode == .datum
                        ? "Pool payouts, and any block mined solo, go to this address. Use an address from your own wallet."
                        : "Blocks you find pay the full reward to this address. Use an address from your own wallet.")
                }
            }

            switch model.config.mode {
            case .datum: DatumSettingsSection()
            case .stratum: HostedGatewaySection()
            case .solo: EmptyView()
            }

            RestartBanner(initial: initial)
        }
        .formStyle(.grouped)
        .onAppear { initial = model.config }
    }
}

/// One mode in the mode picker.
struct ModeChoice: View {
    let title: String
    var recommended = false
    let detail: String
    let buildsBlocks: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(title).fontWeight(.medium)
                if recommended {
                    Text("Recommended")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tint)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(.tint.opacity(0.12), in: Capsule())
                }
                BuilderBadge(youBuild: buildsBlocks, compact: true)
            }
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
    }
}

/// A Bitcoin address field with instant format feedback.
struct AddressField: View {
    let label: String
    @Binding var text: String
    var prompt = "bc1… or 1…"

    var body: some View {
        LabeledContent(label) {
            VStack(alignment: .trailing, spacing: 4) {
                TextField(label, text: $text, prompt: Text(prompt))
                    .labelsHidden()
                    .font(.body.monospaced())
                    .multilineTextAlignment(.trailing)
                switch AddressFormat.check(text) {
                case .empty:
                    EmptyView()
                case .looksValid:
                    Label("Looks valid · Diagnostics checks it with your node", systemImage: "checkmark.circle.fill")
                        .font(.caption).foregroundStyle(.green)
                case .invalid(let why):
                    Label(why, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
        }
    }
}

/// Settings for the gateway the app runs (DATUM mode).
struct DatumSettingsSection: View {
    @EnvironmentObject var model: AppModel
    @State private var showAdvanced = false

    private var pool: DatumPool? { DatumPool.find(model.config.gateway.poolID) }

    var body: some View {
        Section {
            Picker("DATUM pool", selection: $model.config.gateway.poolID) {
                ForEach(DatumPool.all) { Text($0.name).tag($0.id) }
                Divider()
                Text("None, mine solo").tag("")
            }
            if let pool = pool {
                LabeledContent("Fee") {
                    HStack(spacing: 8) {
                        Text(pool.fee)
                        if let url = pool.websiteURL { Link("Website", destination: url) }
                    }
                }
                Toggle("Keep mining solo if \(pool.name) is unreachable", isOn: $model.config.gateway.soloWhenPoolDown)
            }
        } header: {
            Text("DATUM pool")
        } footer: {
            SectionNote(pool == nil
                ? "Solo through your gateway: any block you find pays the full reward to you."
                : "Your node chooses the transactions and builds every block; the pool only coordinates who gets paid, straight from the coinbase. Pooled DATUM needs blockmaxweight=785000 in bitcoin.conf (Diagnostics checks it).")
        }
        Section {
            DisclosureGroup("Advanced", isExpanded: $showAdvanced) {
                TextField("Gateway port", value: $model.config.gateway.stratumPort, format: .number.grouping(.never))
                Toggle("Let other miners on my network use this gateway", isOn: $model.config.gateway.allowNetworkMiners)
                if model.config.gateway.allowNetworkMiners {
                    SectionNote("ASICs and other computers can connect to stratum+tcp://\(LocalNetwork.address ?? "this-mac"):\(model.config.gateway.stratumPort) with their payout address as the username.")
                        .textSelection(.enabled)
                }
            }
        }
    }
}

/// A pool's public gateway (Stratum mode).
struct HostedGatewaySection: View {
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
            if preset == nil {
                TextField("Server", text: $model.config.stratum.url, prompt: Text("host:port or stratum+ssl://host:port"))
            } else if let p = preset {
                LabeledContent("Fee") {
                    HStack(spacing: 8) {
                        Text(p.fee)
                        if let url = p.websiteURL { Link("Website", destination: url) }
                    }
                }
            }
            AddressField(label: "Username", text: $model.config.stratum.user, prompt: "your payout address[.worker]")
            TextField("Password", text: $model.config.stratum.password)
            HStack {
                Button(probing ? "Testing…" : "Test Server") { runProbe() }
                    .disabled(probing || model.config.stratum.url.isEmpty)
                if probing { ProgressView().controlSize(.small) }
            }
            ForEach(probe, id: \.self) { CheckLine(text: $0) }
        } header: {
            Text("Pool-hosted gateway")
        } footer: {
            SectionNote("The pool's node chooses the transactions in the blocks you mine. To build your own blocks, choose \"My own DATUM Gateway\". Pools set the share difficulty for ASICs, so at CPU speed a share can take days.")
        }
    }

    private func runProbe() {
        probing = true
        probe = []
        let config = model.config.stratum
        Task.detached {
            let report = StratumProbe.run(config)
            await MainActor.run {
                probe = report.lines + [report.compatible ? "✅ This server works with BLAKE2b Miner" : "❌ This server can't be used as configured"]
                probing = false
            }
        }
    }
}
