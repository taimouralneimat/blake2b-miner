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
/// opens the dashboard (a menu-bar-only app is otherwise easy to miss), and it
/// opens it whenever the app is opened again while running.
public struct MenuBarItem: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    public init() {}

    public var body: some View {
        MenuBarLabel(status: model.status, isRunning: model.isRunning, showRate: model.prefs.showHashrateInMenuBar)
            .task {
                let firstRun = !model.isConfigured && model.consumeFirstLaunch()
                if firstRun || CommandLine.arguments.contains("--dashboard") { openDashboard() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .openDashboard)) { _ in openDashboard() }
    }

    private func openDashboard() {
        model.page = model.isConfigured ? .overview : .mining
        openWindow(id: MainWindowView.id)
        NSApp.activate(ignoringOtherApps: true)
    }
}

extension Notification.Name {
    /// Posted when the user opens the app again while it's running (Finder, Spotlight, Dock).
    public static let openDashboard = Notification.Name("BLAKE2bMiner.openDashboard")
}
