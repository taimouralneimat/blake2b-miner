import MinerCore
import SwiftUI

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
