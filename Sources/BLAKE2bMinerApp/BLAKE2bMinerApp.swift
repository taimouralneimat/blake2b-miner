import AppKit
import MinerCore
import MinerUI
import SwiftUI

@main
struct BLAKE2bMinerApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
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

        Window("BLAKE2b Miner", id: MainWindowView.id) {
            MainWindowView()
                .environmentObject(model)
        }
        .defaultSize(width: 1040, height: 720)
        .windowResizability(.contentMinSize)
    }
}

/// Opening the app again while it runs (Finder, Spotlight, Dock) shows the dashboard.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        NotificationCenter.default.post(name: .openDashboard, object: nil)
        return false
    }
}
