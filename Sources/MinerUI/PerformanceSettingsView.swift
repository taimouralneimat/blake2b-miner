import MinerCore
import SwiftUI

/// CPU use and how the app behaves.
struct PerformanceSettingsView: View {
    @EnvironmentObject var model: AppModel
    @State private var initial = MinerConfig()

    var body: some View {
        Form {
            Section {
                LabeledContent("Threads") {
                    HStack(spacing: 10) {
                        Slider(value: Binding(get: { Double(model.config.threads) },
                                              set: { model.config.threads = Int($0.rounded()) }),
                               in: 1...Double(max(CPUInfo.cores, 2)), step: 1)
                            .frame(minWidth: 180)
                        Text("\(model.config.threads) of \(CPUInfo.cores)")
                            .monospacedDigit()
                            .frame(width: 64, alignment: .trailing)
                    }
                }
                Toggle("Keep the Mac responsive", isOn: $model.config.lowPriority)
            } header: {
                Text("CPU")
            } footer: {
                SectionNote("More threads mine faster. Keeping the Mac responsive runs mining at a lower priority so other apps come first, at a small cost in hashrate.")
            }

            Section("Power") {
                Toggle("Pause while on battery power", isOn: $model.config.pauseOnBattery)
                Toggle("Keep the Mac awake while mining", isOn: $model.config.preventSleep)
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
