import MinerCore
import SwiftUI

/// Checks of the node setup and of the hashing itself.
struct DiagnosticsView: View {
    @EnvironmentObject var model: AppModel
    @State private var nodeReport: [String] = []
    @State private var testResults: [SelfTest.Result] = []
    @State private var running = false
    @State private var lastRun: Date?

    var body: some View {
        Form {
            Section {
                HStack(spacing: 10) {
                    Button { runAll() } label: {
                        Label(running ? "Checking…" : "Run All Checks", systemImage: "stethoscope")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(running)
                    if running { ProgressView().controlSize(.small) }
                    Spacer()
                    if let lastRun = lastRun, !running {
                        Text("Last run \(lastRun, style: .time)").font(.caption).foregroundStyle(.secondary)
                    }
                }
            } footer: {
                SectionNote("Checks that your node is reachable, synced and on the BLAKE2b chain, that your payout address is valid and in your wallet, and that the hashing matches the official Bitcoin Knots test vectors and your node's recent blocks.")
            }

            if !nodeReport.isEmpty {
                Section("Your node") {
                    ForEach(nodeReport, id: \.self) { CheckLine(text: $0) }
                }
            }

            if !testResults.isEmpty {
                Section("Hashing") {
                    ForEach(testResults, id: \.name) { r in
                        CheckLine(text: (r.passed ? "✅ " : "❌ ") + "\(r.name): \(r.detail)")
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func runAll() {
        running = true
        nodeReport = []
        testResults = []
        let config = model.config
        Task.detached {
            let lines = NodeCheck.run(config)
            await MainActor.run { nodeReport = lines }
            let results = SelfTest.run(node: config.node)
            await MainActor.run {
                testResults = results
                running = false
                lastRun = Date()
            }
        }
    }
}
