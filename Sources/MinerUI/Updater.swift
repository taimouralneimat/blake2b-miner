import AppKit
import MinerCore
import SwiftUI

/// Checks GitHub for new releases (at launch and daily, unless turned off) and
/// installs one on request: download, checksum, unpack, check it is this app at the
/// promised version, then quit, swap the app in place, and reopen it.
@MainActor
public final class Updater: ObservableObject {
    public enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(UpdateCheck.Release)
        case downloading(UpdateCheck.Release)
        case failed(String, UpdateCheck.Release?)
    }

    @Published public private(set) var state: State = .idle
    /// Check at launch and once a day.
    @Published public var automatic: Bool {
        didSet { UserDefaults.standard.set(automatic, forKey: Keys.automatic) }
    }

    private let isLive: Bool
    private var timer: Timer?

    private enum Keys {
        static let automatic = "checkForUpdates"
        static let skipped = "skippedUpdateVersion"
    }

    private static let firstCheckDelay: TimeInterval = 10
    private static let checkInterval: TimeInterval = 24 * 3600

    public init(isLive: Bool = true) {
        self.isLive = isLive
        automatic = UserDefaults.standard.object(forKey: Keys.automatic) as? Bool ?? true
    }

    /// For previews and snapshots: a fixed state.
    public convenience init(preview state: State) {
        self.init(isLive: false)
        self.state = state
    }

    /// Starts the launch and daily checks (each skipped while `automatic` is off).
    func startAutomaticChecks() {
        guard isLive, timer == nil else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.firstCheckDelay) { [weak self] in
            self?.checkIfAutomatic()
        }
        timer = Timer.scheduledTimer(withTimeInterval: Self.checkInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkIfAutomatic() }
        }
    }

    private func checkIfAutomatic() {
        if automatic { check(userInitiated: false) }
    }

    /// Asks GitHub for the latest release. A skipped version is only offered again
    /// when you check yourself.
    public func check(userInitiated: Bool) {
        guard isLive else { return }
        switch state {
        case .checking, .downloading: return
        default: break
        }
        state = .checking
        Task {
            do {
                let release = try await UpdateCheck.latest()
                let skipped = UserDefaults.standard.string(forKey: Keys.skipped)
                if UpdateCheck.isNewer(release.version, than: Miner.version), userInitiated || release.version != skipped {
                    state = .available(release)
                } else {
                    state = .upToDate
                }
            } catch {
                state = userInitiated ? .failed("Couldn't check for updates: \(error.localizedDescription)", nil) : .idle
            }
        }
    }

    /// Don't offer this version again automatically.
    public func skip() {
        guard case .available(let release) = state else { return }
        UserDefaults.standard.set(release.version, forKey: Keys.skipped)
        state = .idle
    }

    public func dismiss() { state = .idle }

    public func openReleasePage() {
        let page: URL?
        switch state {
        case .available(let r), .downloading(let r), .failed(_, let r?): page = r.page
        default: page = URL(string: "https://github.com/\(UpdateCheck.repository)/releases")
        }
        if let page = page { NSWorkspace.shared.open(page) }
    }

    /// Downloads, checks and installs the release, then quits so the new version opens
    /// in its place. On any problem the current app stays as it is.
    public func install() {
        guard case .available(let release) = state else { return }
        state = .downloading(release)
        Task {
            do {
                let zip = try await UpdateCheck.download(release)
                let newApp = try Self.unpack(zip, expecting: release.version)
                try Self.replaceAfterQuit(with: newApp)
                NSApp.terminate(nil)  // stops mining cleanly; the helper waits, swaps and reopens
            } catch {
                state = .failed("The update couldn't be installed: \(error.localizedDescription)", release)
            }
        }
    }

    /// Unzips the release and checks it is this app (same bundle identifier) at the
    /// promised version.
    private static func unpack(_ zip: URL, expecting version: String) throws -> URL {
        let folder = zip.deletingLastPathComponent().appendingPathComponent("unpacked")
        try? FileManager.default.removeItem(at: folder)
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-x", "-k", zip.path, folder.path]
        try ditto.run()
        ditto.waitUntilExit()
        guard ditto.terminationStatus == 0,
              let app = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
                .first(where: { $0.pathExtension == "app" }),
              let bundle = Bundle(url: app) else {
            throw MinerError.config("the download doesn't contain the app")
        }
        guard bundle.bundleIdentifier == Bundle.main.bundleIdentifier,
              bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String == version else {
            throw MinerError.config("the download isn't BLAKE2b Miner \(version)")
        }
        return app
    }

    /// Starts a helper that waits for this app to quit, puts the new app where this
    /// one is (keeping the old one if the swap fails), and opens it.
    private static func replaceAfterQuit(with newApp: URL) throws {
        let current = Bundle.main.bundleURL
        guard current.pathExtension == "app",
              FileManager.default.isWritableFile(atPath: current.deletingLastPathComponent().path) else {
            throw MinerError.config("this copy of the app (\(current.path)) can't be replaced; install it from the release page")
        }
        let script = """
        while kill -0 "$1" 2>/dev/null; do sleep 0.5; done
        rm -rf "$2.old"
        if mv "$2" "$2.old" && ditto "$3" "$2"; then rm -rf "$2.old"; else rm -rf "$2"; mv "$2.old" "$2"; fi
        open "$2"
        """
        let helper = Process()
        helper.executableURL = URL(fileURLWithPath: "/bin/sh")
        helper.arguments = ["-c", script, "update", String(ProcessInfo.processInfo.processIdentifier), current.path, newApp.path]
        try helper.run()
    }
}

/// The offer of a new version, shown on the dashboard and in the menu.
struct UpdateBanner: View {
    @ObservedObject var updater: Updater
    var compact = false

    var body: some View {
        switch updater.state {
        case .available(let release):
            VStack(alignment: .leading, spacing: 8) {
                Label("BLAKE2b Miner \(release.version) is available (you have \(Miner.version)).", systemImage: "arrow.down.circle.fill")
                    .font(.callout.weight(.medium))
                HStack {
                    Button("Install Update") { updater.install() }.buttonStyle(.borderedProminent)
                    Button(compact ? "Notes" : "Release Notes") { updater.openReleasePage() }
                    if !compact { Button("Skip This Version") { updater.skip() } }
                }
                .controlSize(compact ? .small : .regular)
            }
            .padding(compact ? 10 : 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
        case .downloading(let release):
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Downloading and checking \(release.version)… the app restarts when it's ready.").font(.callout)
            }
        case .failed(let message, _):
            VStack(alignment: .leading, spacing: 6) {
                Label(message, systemImage: "exclamationmark.triangle.fill").font(.callout).foregroundStyle(.orange)
                HStack {
                    Button("Open Release Page") { updater.openReleasePage() }
                    Button("Dismiss") { updater.dismiss() }
                }
                .controlSize(.small)
            }
        default:
            EmptyView()
        }
    }
}
