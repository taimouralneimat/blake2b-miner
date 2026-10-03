import AppKit
import MinerCore
import SwiftUI

/// The main window: a sidebar of pages and the selected page. Resizable and
/// full-screen capable. While it is open the app shows in the Dock and the app
/// switcher like a normal app; when it closes the app is menu-bar only again.
public struct MainWindowView: View {
    /// The window's scene id, for `openWindow(id:)`.
    public static let id = "main"

    @EnvironmentObject var model: AppModel

    public init() {}

    public var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            page(model.page)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle(model.page.title)
        }
        .frame(minWidth: 860, minHeight: 580)
        .onAppear { setInDock(true) }
        .onDisappear { setInDock(false) }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        List(selection: Binding<Page?>(get: { model.page }, set: { if let p = $0 { model.page = p } })) {
            ForEach(Page.groups.indices, id: \.self) { i in
                let group = Page.groups[i]
                Section {
                    ForEach(group.pages) { p in
                        Label(p.title, systemImage: p.icon).tag(p)
                    }
                } header: {
                    if let title = group.title { Text(title) }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 260)
        .safeAreaInset(edge: .bottom) { sidebarStatus }
    }

    /// A small live status at the bottom of the sidebar, visible on every page.
    private var sidebarStatus: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
            HStack(spacing: 8) {
                StatePill(state: model.isRunning ? model.status.state : .stopped)
                if model.isRunning && model.status.state == .mining {
                    Text(formatHashrate(model.status.hashrate))
                        .font(.callout.weight(.medium))
                        .monospacedDigit()
                }
                Spacer()
            }
            BuilderBadge(youBuild: model.config.mode.youBuildTheBlocks)
            startStopButton
                .padding(.top, 2)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
    }

    /// Start/Stop, reachable from every page.
    @ViewBuilder private var startStopButton: some View {
        if !model.isConfigured {
            Button { model.page = .mining } label: { Label("Set Up", systemImage: "gearshape").frame(maxWidth: .infinity) }
        } else if model.isRunning {
            Button { model.stop() } label: { Label("Stop Mining", systemImage: "stop.fill").frame(maxWidth: .infinity) }
        } else {
            Button { model.start() } label: { Label("Start Mining", systemImage: "play.fill").frame(maxWidth: .infinity) }
                .buttonStyle(.borderedProminent)
                .tint(.green)
        }
    }

    // MARK: Pages

    @ViewBuilder private func page(_ page: Page) -> some View {
        switch page {
        case .overview: DashboardView()
        case .mining: Readable { MiningSettingsView() }
        case .performance: Readable { PerformanceSettingsView() }
        case .node: Readable { NodeSettingsView() }
        case .diagnostics: Readable { DiagnosticsView() }
        case .log: LogView()
        case .about: AboutView()
        }
    }

    private func setInDock(_ inDock: Bool) {
        guard Bundle.main.bundleIdentifier != nil else { return }  // not in previews or snapshots
        NSApp.setActivationPolicy(inDock ? .regular : .accessory)
        if inDock { NSApp.activate(ignoringOtherApps: true) }
    }
}

/// Keeps forms at a comfortable reading width in a wide or full-screen window.
struct Readable<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
    }
}
