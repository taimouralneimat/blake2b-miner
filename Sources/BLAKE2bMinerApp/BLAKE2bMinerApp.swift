import AppKit
import MinerCore
import MinerUI
import SwiftUI

@main
struct BLAKE2bMinerApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    @StateObject private var model = AppModel()

    init() {
        AppDelegate.quitIfAlreadyRunning()
    }

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

/// Opening the app again while it runs (Finder, Spotlight, Dock) shows the dashboard,
/// even when that opens a second copy of the app from another folder.
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Sent by a second copy of the app to the one already running.
    private static let showDashboard = Notification.Name("BLAKE2bMiner.showDashboard")

    /// Called before anything else starts: if another copy is running (say, one in
    /// /Applications and one in a build folder), show its dashboard and exit, so two
    /// copies never mine at once.
    static func quitIfAlreadyRunning() {
        guard let id = Bundle.main.bundleIdentifier else { return }
        let me = NSRunningApplication.current
        // Only the newer copy quits, so two copies opened at the same moment don't both exit.
        func launchedFirst(_ a: NSRunningApplication, _ b: NSRunningApplication) -> Bool {
            let (da, db) = (a.launchDate ?? .distantPast, b.launchDate ?? .distantPast)
            return da != db ? da < db : a.processIdentifier < b.processIdentifier
        }
        guard let other = NSRunningApplication.runningApplications(withBundleIdentifier: id)
            .first(where: { $0.processIdentifier != me.processIdentifier && !$0.isTerminated && launchedFirst($0, me) }) else { return }
        DistributedNotificationCenter.default().postNotificationName(showDashboard, object: nil,
                                                                     userInfo: nil, deliverImmediately: true)
        other.activate()
        exit(0)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        DistributedNotificationCenter.default().addObserver(forName: Self.showDashboard, object: nil, queue: .main) { _ in
            NotificationCenter.default.post(name: .openDashboard, object: nil)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        NotificationCenter.default.post(name: .openDashboard, object: nil)
        return false
    }
}
