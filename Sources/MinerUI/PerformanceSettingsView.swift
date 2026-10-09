import MinerCore
import SwiftUI

/// What mines (CPU threads, the GPU, or both), how hard, and how the app behaves.
struct PerformanceSettingsView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Form {
            Section {
                Toggle("Mine with the CPU", isOn: $model.config.useCPU)
                    // At least one of CPU and GPU stays on.
                    .disabled(model.config.useCPU && !model.config.useGPU)
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
                .disabled(!model.config.useCPU)
            } header: {
                Text("CPU")
            } footer: {
                SectionNote(cpuNote)
            }

            Section {
                if let gpu = GPUInfo.name {
                    Toggle("Mine with the GPU (\(gpu))", isOn: $model.config.useGPU)
                        .disabled(model.config.useGPU && !model.config.useCPU)
                    LabeledContent("GPU load") {
                        HStack(spacing: 10) {
                            Slider(value: Binding(get: { Double(model.config.gpuLoad) },
                                                  set: { model.config.gpuLoad = Int($0.rounded()) }),
                                   in: 10...100, step: 10)
                                .frame(minWidth: 180)
                            Text("\(model.config.gpuLoad)%")
                                .monospacedDigit()
                                .frame(width: 64, alignment: .trailing)
                        }
                    }
                    .disabled(!model.config.useGPU)
                } else {
                    Text("This Mac has no Metal GPU, so it mines with the CPU only.")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("GPU")
            } footer: {
                if GPUInfo.name != nil {
                    SectionNote("On Apple Silicon the GPU is usually the fastest hasher, often twice the CPU or more. With the GPU on, leaving a couple of CPU cores free helps keep it fed. A lower load leaves more of the GPU for graphics and makes less heat; the fans may run while mining.")
                }
            }

            Section {
                Toggle("Keep the Mac responsive", isOn: $model.config.lowPriority)
            } header: {
                Text("Responsiveness")
            } footer: {
                SectionNote("Applies to both. CPU mining runs at low priority so other apps come first; macOS then runs it mostly on the efficiency cores, which can halve the CPU hashrate. The GPU gets its work in short bursts so animations and video stay smooth, for about 10% less GPU hashrate.")
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

            RestartBanner()
        }
        .formStyle(.grouped)
    }

    private var cpuNote: String {
        let p = CPUInfo.performanceCores
        guard p < CPUInfo.cores else { return "More threads mine faster." }
        return "More threads mine faster. This Mac has \(p) performance cores and \(CPUInfo.cores - p) efficiency cores; threads beyond \(p) run on the efficiency cores and add less."
    }
}
