import AppKit
import Foundation
import MinerCore
import ServiceManagement
import UserNotifications

/// Settings that only matter to the app (the miner itself uses MinerConfig).
struct AppPreferences: Codable, Equatable {
    var startMiningAtLaunch = false
    var showHashrateInMenuBar = true

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        startMiningAtLaunch = c.decode(.startMiningAtLaunch, or: false)
        showHashrateInMenuBar = c.decode(.showHashrateInMenuBar, or: true)
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var config: MinerConfig { didSet { save() } }
    @Published var prefs: AppPreferences { didSet { save() } }
    @Published private(set) var status = MinerStatus()
    @Published private(set) var log: [LogLine] = []
    @Published private(set) var foundBlocks: [FoundBlock] = FoundBlocks.all()
    @Published private(set) var isRunning = false
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled

    private let miner = Miner()
    private let bridge = Bridge()
    private let logFile = LogFile()

    init() {
        let d = UserDefaults.standard
        var loaded = d.data(forKey: Keys.config).flatMap { try? JSONDecoder().decode(MinerConfig.self, from: $0) } ?? MinerConfig()
        if loaded.node.rpcPassword.isEmpty {
            loaded.node.rpcPassword = Keychain.read(Keys.rpcPassword) ?? ""
        } else {
            Keychain.write(Keys.rpcPassword, loaded.node.rpcPassword)  // migrate from the preferences file
        }
        loaded.threads = min(max(loaded.threads, 1), CPUInfo.cores)
        config = loaded
        prefs = d.data(forKey: Keys.prefs).flatMap { try? JSONDecoder().decode(AppPreferences.self, from: $0) } ?? AppPreferences()
        save()  // rewrites the stored settings without the password
        bridge.model = self
        miner.delegate = bridge
        // Stop cleanly on quit (including logout/shutdown) so the gateway exits too.
        let m = miner
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: nil) { _ in
            m.stop()
        }
        if prefs.startMiningAtLaunch && isConfigured { start() }
    }

    /// What the Keychain currently holds, to avoid rewriting it on every keystroke.
    private var keychainPassword: String?

    private enum Keys {
        static let config = "minerConfig"
        static let prefs = "appPreferences"
        static let rpcPassword = "rpcPassword"
    }

    /// Settings go to UserDefaults; the RPC password goes to the Keychain only.
    private func save() {
        var stored = config
        stored.node.rpcPassword = ""
        if config.node.rpcPassword != keychainPassword {
            Keychain.write(Keys.rpcPassword, config.node.rpcPassword)
            keychainPassword = config.node.rpcPassword
        }
        let d = UserDefaults.standard
        d.set(try? JSONEncoder().encode(stored), forKey: Keys.config)
        d.set(try? JSONEncoder().encode(prefs), forKey: Keys.prefs)
    }

    /// Enough settings to start mining.
    var isConfigured: Bool {
        switch config.mode {
        case .solo, .datum: return !config.payoutAddress.trimmingCharacters(in: .whitespaces).isEmpty
        case .stratum: return !config.stratum.user.isEmpty && !config.stratum.url.isEmpty
        }
    }

    func start() {
        guard !isRunning, isConfigured else { return }
        isRunning = true
        status = MinerStatus()
        status.state = .starting
        status.mode = config.mode
        requestNotificationPermission()
        miner.start(config)
    }

    func stop() {
        guard isRunning else { return }
        let m = miner
        Task.detached {
            m.stop()  // joins engine threads; off the main thread to keep the UI responsive
            await MainActor.run { self.markStopped() }
        }
    }

    /// Restart with new settings if currently mining.
    func applySettings() {
        guard isRunning else { return }
        let m = miner
        Task.detached {
            m.stop()
            await MainActor.run {
                self.markStopped()
                self.start()
            }
        }
    }

    private func markStopped() {
        isRunning = false
        status.state = .stopped
        status.hashrate = 0
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            append(log: "Could not change Open at Login: \(error.localizedDescription)")
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func revealLogFile() { NSWorkspace.shared.activateFileViewerSelecting([logFile.url]) }

    func revealFoundBlocks() {
        let url = FileManager.default.fileExists(atPath: FoundBlocks.file.path) ? FoundBlocks.file : FoundBlocks.directory
        try? FileManager.default.createDirectory(at: FoundBlocks.directory, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: Updates from the miner (via Bridge, on the main actor)

    fileprivate func append(log line: String) {
        let stamped = Self.timeFormatter.string(from: Date()) + "  " + line
        nextLogID += 1
        log.append(LogLine(id: nextLogID, text: stamped))
        if log.count > Self.logLinesKept { log.removeFirst(log.count - Self.logLinesKept) }
        logFile.write(stamped)
    }

    fileprivate func update(_ s: MinerStatus) {
        guard isRunning else { return }  // ignore late updates from a stopped session
        status = s
        if s.state == .mining, Date().timeIntervalSince(lastRateLog) >= Self.rateLogInterval {
            lastRateLog = Date()
            var line = "Hashrate \(formatHashrate(s.hashrate)), average \(formatHashrate(s.averageHashrate))"
            if let e = s.expectedSecondsPerBlock { line += ", expected time per block ≈ \(formatDuration(e))" }
            if s.mode == .stratum { line += ", shares \(s.sharesAccepted) accepted / \(s.sharesRejected) rejected" }
            append(log: line)
        }
    }

    private var lastRateLog = Date()
    private var nextLogID = 0
    /// Lines shown in the Log window (the log file keeps everything).
    private static let logLinesKept = 1000
    /// How often the hashrate is written to the log while mining.
    private static let rateLogInterval: TimeInterval = 600

    fileprivate func found(_ block: FoundBlock) {
        FoundBlocks.append(block)
        foundBlocks = FoundBlocks.all()
        let content = UNMutableNotificationContent()
        content.title = block.isAccepted ? "Block found! 🎉" : "Block solved but not accepted"
        content.body = "Height \(block.height): \(block.result)\n\(block.hash)"
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: block.hash, content: content, trigger: nil))
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()
}

/// Receives callbacks on the miner's control thread and forwards them to the main actor.
private final class Bridge: MinerDelegate {
    weak var model: AppModel?

    func miner(log line: String) {
        Task { @MainActor [weak model] in model?.append(log: line) }
    }

    func miner(status: MinerStatus) {
        Task { @MainActor [weak model] in model?.update(status) }
    }

    func miner(found block: FoundBlock) {
        Task { @MainActor [weak model] in model?.found(block) }
    }
}

/// One line in the Log window; `id` stays stable as old lines are dropped.
struct LogLine: Identifiable {
    let id: Int
    let text: String
}

/// ~/Library/Logs/BLAKE2bMiner/miner.log, rotated at 5 MB.
private final class LogFile {
    let url: URL
    private static let maxSize = 5_000_000

    init() {
        let dir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/BLAKE2bMiner", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("miner.log")
    }

    func write(_ line: String) {
        let data = Data((line + "\n").utf8)
        if let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int, size > Self.maxSize {
            let old = url.deletingPathExtension().appendingPathExtension("1.log")
            try? FileManager.default.removeItem(at: old)
            try? FileManager.default.moveItem(at: url, to: old)
        }
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile()
            h.write(data)
            try? h.close()
        } else {
            try? data.write(to: url)
        }
    }
}
