import MinerCore
import MinerUI
import SwiftUI

@main
struct BLAKE2bMinerApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuView()
                .environmentObject(model)
        } label: {
            MenuBarItem()
                .environmentObject(model)
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
