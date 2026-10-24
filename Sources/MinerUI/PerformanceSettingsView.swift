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
                    SectionNote("On Apple Silicon the GPU is usually the fastest hasher, often twice the CPU or more; use it together with all CPU threads for the most hashrate. A lower load leaves more of the GPU for graphics and makes less heat; the fans may run while mining.")
                }
            }

            Section {
                Picker("Keep the Mac responsive", selection: responsiveMode) {
                    Text("Never").tag(ResponsiveMode.never)
                    Text("Always").tag(ResponsiveMode.always)
                    Text("On a schedule").tag(ResponsiveMode.scheduled)
                }
                if responsiveMode.wrappedValue == .scheduled {
                    LabeledContent("Hours") {
                        HStack(spacing: 6) {
                            DatePicker("From", selection: scheduleTime(\.start), displayedComponents: .hourAndMinute)
                                .labelsHidden()
                            Text("to")
                            DatePicker("To", selection: scheduleTime(\.end), displayedComponents: .hourAndMinute)
                                .labelsHidden()
                        }
                    }
                    LabeledContent("Days") {
                        HStack(spacing: 4) {
                            ForEach(ResponsiveSchedule.orderedDays(), id: \.weekday) { day in
                                let on = model.config.responsiveSchedule.days.contains(day.weekday)
                                Button { dayBinding(day.weekday).wrappedValue.toggle() } label: {
                                    Text(day.name)
                                        .font(.callout.weight(on ? .semibold : .regular))
                                        .frame(minWidth: 38)
                                        .padding(.vertical, 4)
                                        .foregroundStyle(on ? Color.white : Color.primary)
                                        .background(on ? Color.accentColor : Color.secondary.opacity(0.15),
                                                    in: RoundedRectangle(cornerRadius: 6))
                                }
                                .buttonStyle(.plain)
                                .accessibilityAddTraits(on ? .isSelected : [])
                            }
                        }
                    }
                    LabeledContent("Now") {
                        Text(model.config.responsiveSchedule.explanation(at: Date()))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                    }
                }
            } header: {
                Text("Responsiveness")
            } footer: {
                SectionNote("Responsive means other apps come first: the CPU part mines about half as fast, the GPU part 5–15% slower. On a schedule, mining switches at the start and end of your hours without stopping, so it runs at full power while you're away.")
            }

            Section {
                Toggle("Pause while on battery power", isOn: $model.config.pauseOnBattery)
                Toggle("Keep the Mac awake while mining", isOn: $model.config.preventSleep)
            } header: {
                Text("Power")
            } footer: {
                SectionNote("A Mac that sleeps mines only in short wake-ups, at about half speed. Keeping it awake works on mains power only; the display still turns off.")
            }

            Section("App") {
                Toggle("Open at login", isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
                Toggle("Start mining when the app opens", isOn: $model.prefs.startMiningAtLaunch)
                Toggle("Show hashrate in the menu bar", isOn: $model.prefs.showHashrateInMenuBar)
                AutomaticUpdatesToggle(updater: model.updater)
            }

            RestartBanner()
        }
        .formStyle(.grouped)
    }

    private enum ResponsiveMode { case never, always, scheduled }

    private var responsiveMode: Binding<ResponsiveMode> {
        Binding(get: {
            model.config.lowPriority ? .always : model.config.responsiveSchedule.enabled ? .scheduled : .never
        }, set: { mode in
            model.config.lowPriority = mode == .always
            model.config.responsiveSchedule.enabled = mode == .scheduled
        })
    }

    private func dayBinding(_ weekday: Int) -> Binding<Bool> {
        Binding(get: { model.config.responsiveSchedule.days.contains(weekday) }, set: { on in
            if on { model.config.responsiveSchedule.days.insert(weekday) } else { model.config.responsiveSchedule.days.remove(weekday) }
        })
    }

    /// A schedule time (minutes after midnight) as a Date for a time picker.
    private func scheduleTime(_ key: WritableKeyPath<ResponsiveSchedule, Int>) -> Binding<Date> {
        Binding(get: {
            Calendar.current.startOfDay(for: Date()).addingTimeInterval(Double(model.config.responsiveSchedule[keyPath: key]) * 60)
        }, set: { date in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            model.config.responsiveSchedule[keyPath: key] = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        })
    }

    private var cpuNote: String {
        let p = CPUInfo.performanceCores
        guard p < CPUInfo.cores else { return "More threads mine faster." }
        return "More threads mine faster. This Mac has \(p) performance cores and \(CPUInfo.cores - p) efficiency cores; threads beyond \(p) run on the efficiency cores and add less."
    }
}

private struct AutomaticUpdatesToggle: View {
    @ObservedObject var updater: Updater

    var body: some View {
        Toggle("Check for updates automatically", isOn: $updater.automatic)
    }
}
