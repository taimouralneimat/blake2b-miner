import MinerCore
import SwiftUI

public struct MenuBarLabel: View {
    let status: MinerStatus
    let isRunning: Bool
    let showRate: Bool

    public init(status: MinerStatus, isRunning: Bool, showRate: Bool) {
        self.status = status
        self.isRunning = isRunning
        self.showRate = showRate
    }

    public var body: some View {
        HStack(spacing: 4) {
            Image(systemName: isRunning ? "cube.fill" : "cube")
            if isRunning && showRate && status.hashrate > 0 {
                Text(formatHashrate(status.hashrate))
                    .monospacedDigit()
            }
        }
    }
}

/// The menu-bar item. On first launch, when nothing is configured yet, it also
/// opens Settings: a menu-bar-only app is otherwise easy to miss.
public struct MenuBarItem: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    public init() {}

    public var body: some View {
        MenuBarLabel(status: model.status, isRunning: model.isRunning, showRate: model.prefs.showHashrateInMenuBar)
            .task {
                guard !model.isConfigured, model.consumeFirstLaunch() else { return }
                model.settingsTab = .general
                openWindow(id: "settings")
                NSApp.activate(ignoringOtherApps: true)
            }
    }
}
