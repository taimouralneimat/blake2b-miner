import MinerCore
import SwiftUI

@main
struct BLAKE2bMinerApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuView()
                .environmentObject(model)
        } label: {
            MenuBarLabel(status: model.status, isRunning: model.isRunning, showRate: model.prefs.showHashrateInMenuBar)
        }
        .menuBarExtraStyle(.window)

        Window("BLAKE2b Miner Settings", id: "settings") {
            SettingsView()
                .environmentObject(model)
        }
        .windowResizability(.contentSize)

        Window("BLAKE2b Miner Log", id: "log") {
            LogView()
                .environmentObject(model)
        }
    }
}

struct MenuBarLabel: View {
    let status: MinerStatus
    let isRunning: Bool
    let showRate: Bool

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: isRunning ? "cube.fill" : "cube")
            if isRunning && showRate && status.hashrate > 0 {
                Text(formatHashrate(status.hashrate))
                    .monospacedDigit()
            }
        }
    }
}
