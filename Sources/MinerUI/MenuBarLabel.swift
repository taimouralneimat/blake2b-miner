import AppKit
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
            Image(nsImage: isRunning ? MenuBarGlyph.mining : MenuBarGlyph.idle)
            if isRunning && showRate && status.hashrate > 0 {
                Text(formatHashrate(status.hashrate))
                    .monospacedDigit()
            }
        }
    }
}

/// The menu-bar glyph, after the app icon: a display with a block on its screen,
/// solid while mining and outlined when not. A template image, so macOS colors it
/// for light and dark menu bars.
enum MenuBarGlyph {
    static let mining = image(solidBlock: true)
    static let idle = image(solidBlock: false)

    private static func image(solidBlock: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 16), flipped: true) { _ in
            NSColor.black.setStroke()
            let display = NSBezierPath(roundedRect: NSRect(x: 1, y: 1, width: 16, height: 10.5), xRadius: 2.2, yRadius: 2.2)
            display.lineWidth = 1.4
            display.stroke()
            let stand = NSBezierPath()
            stand.move(to: NSPoint(x: 9, y: 11.5))
            stand.line(to: NSPoint(x: 9, y: 14.5))
            stand.move(to: NSPoint(x: 5.5, y: 14.8))
            stand.line(to: NSPoint(x: 12.5, y: 14.8))
            stand.lineWidth = 1.4
            stand.lineCapStyle = .round
            stand.stroke()
            drawBlock(center: NSPoint(x: 9, y: 6.3), radius: 3.4, solid: solidBlock)
            return true
        }
        image.isTemplate = true
        return image
    }

    /// An isometric block; its faces are shaded by opacity, which template images keep.
    private static func drawBlock(center c: NSPoint, radius r: CGFloat, solid: Bool) {
        let h = r * 0.866
        let top = NSPoint(x: c.x, y: c.y - r), bottom = NSPoint(x: c.x, y: c.y + r)
        let ul = NSPoint(x: c.x - h, y: c.y - r / 2), ur = NSPoint(x: c.x + h, y: c.y - r / 2)
        let ll = NSPoint(x: c.x - h, y: c.y + r / 2), lr = NSPoint(x: c.x + h, y: c.y + r / 2)
        func face(_ points: [NSPoint]) -> NSBezierPath {
            let path = NSBezierPath()
            path.move(to: points[0])
            points.dropFirst().forEach(path.line(to:))
            path.close()
            return path
        }
        let faces = [(face([top, ur, c, ul]), 1.0), (face([ul, c, bottom, ll]), 0.7), (face([c, ur, lr, bottom]), 0.45)]
        if solid {
            for (path, alpha) in faces {
                NSColor.black.withAlphaComponent(alpha).setFill()
                path.fill()
            }
        } else {
            NSColor.black.setStroke()
            for (path, _) in faces {
                path.lineWidth = 0.9
                path.lineJoinStyle = .round
                path.stroke()
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
