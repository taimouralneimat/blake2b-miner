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
                Text("Hardware")
            } footer: {
                SectionNote(hardwareNote)
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
                SectionNote("Other apps come first: the CPU part mines about half as fast, the GPU part 5–15% slower. On a schedule it switches without stopping, and runs at full power outside your hours.")
            }

            Section {
                Toggle("Pause while on battery power", isOn: $model.config.pauseOnBattery)
                Toggle("Keep the Mac awake while mining", isOn: $model.config.preventSleep)
                Toggle("Open at login", isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
                Toggle("Start mining when the app opens", isOn: $model.prefs.startMiningAtLaunch)
                Toggle("Show hashrate in the menu bar", isOn: $model.prefs.showHashrateInMenuBar)
            } header: {
                Text("Power and startup")
            } footer: {
                SectionNote("A sleeping Mac mines at about half speed. Keeping it awake works on mains power; the display still turns off. Automatic updates are on the About page.")
            }
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

    private var hardwareNote: String {
        let p = CPUInfo.performanceCores
        let cpu = p < CPUInfo.cores ? "Threads beyond \(p) use the efficiency cores and add less. " : ""
        return GPUInfo.name == nil ? cpu + "More threads mine faster."
            : cpu + "The GPU is usually the fastest hasher; use it with all CPU threads for the most hashrate."
    }
}
