import AppKit
import Foundation
import MinerCore
import ServiceManagement
import UserNotifications

/// Settings that only matter to the app (the miner itself uses MinerConfig).
public struct AppPreferences: Codable, Equatable {
    var startMiningAtLaunch = false
    public var showHashrateInMenuBar = true

    init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        startMiningAtLaunch = c.decode(.startMiningAtLaunch, or: false)
        showHashrateInMenuBar = c.decode(.showHashrateInMenuBar, or: true)
    }
}

@MainActor
public final class AppModel: ObservableObject {
    @Published var config: MinerConfig { didSet { save() } }
    @Published public var prefs: AppPreferences { didSet { save() } }
    @Published public private(set) var status = MinerStatus()
    @Published private(set) var log: [LogLine] = []
    @Published private(set) var foundBlocks: [FoundBlock]
    @Published public private(set) var isRunning = false
    /// The page the main window shows; the menu sets it to jump to a page.
    @Published public var page: Page = .overview
    /// Recent hashrate, about one sample every 10 seconds, for the dashboard chart.
    @Published public private(set) var history: [HashrateSample] = []
    @Published var launchAtLogin: Bool
    /// What the pool reports about your address (pools with a statistics API).
    @Published private(set) var poolAccount: PoolAccount?
    @Published private(set) var poolAccountUpdated: Date?
    @Published private(set) var poolAccountError: String?
    private var poolAccountTask: Task<Void, Never>?
    private var waitingCheckTask: Task<Void, Never>?
    /// Every pool that has known your address (current one included), with what it
    /// last reported: a pool you left can still owe you.
    @Published private(set) var poolRecords: [PoolRecord] = []

    /// Each built-in pool's size, for the Pools page (by pool id).
    @Published private(set) var poolOverviews: [String: PoolOverview] = [:]
    @Published private(set) var poolOverviewsUpdated: Date?
    /// Payouts to your address, from the node's wallet; nil until read, or when no
    /// loaded wallet has the address.
    @Published private(set) var earnings: Earnings.Summary?
    @Published private(set) var earningsChecked = false
    private var earningsAddress: String?
    @Published private(set) var earningsError: String?

    /// New releases on GitHub.
    public let updater: Updater
    private let miner = Miner()
    private let bridge = Bridge()
    private let logFile = LogFile()
    /// False for previews: nothing is saved, started or written to disk.
    private let isLive: Bool

    public init() {
        isLive = true
        updater = Updater()
        let d = UserDefaults.standard
        var loaded = d.data(forKey: Keys.config).flatMap { try? JSONDecoder().decode(MinerConfig.self, from: $0) } ?? MinerConfig()
        let stored = Keychain.read(Keys.rpcPassword) ?? ""
        if loaded.node.rpcPassword.isEmpty {
            loaded.node.rpcPassword = stored
        }  // else: migrate from the preferences file, which save() below does
        // What the Keychain holds now: save() writes only a changed password, so a
        // Keychain that can't be read (e.g. locked) is never overwritten with "".
        keychainPassword = stored
        loaded.threads = min(max(loaded.threads, 1), CPUInfo.cores)
        loaded.gpuLoad = min(max(loaded.gpuLoad, 10), 100)
        if GPUInfo.name == nil { loaded.useGPU = false }  // settings from a Mac with a GPU
        if !loaded.useCPU && !loaded.useGPU { loaded.useCPU = true }
        config = loaded
        prefs = d.data(forKey: Keys.prefs).flatMap { try? JSONDecoder().decode(AppPreferences.self, from: $0) } ?? AppPreferences()
        foundBlocks = FoundBlocks.all()
        poolRecords = d.data(forKey: Keys.poolRecords).flatMap { try? JSONDecoder().decode([PoolRecord].self, from: $0) } ?? []
        launchAtLogin = Self.refreshLoginItem()
        save()  // rewrites the stored settings without the password
        bridge.model = self
        miner.delegate = bridge
        // Stop cleanly on quit (including logout/shutdown) so the gateway exits too.
        let m = miner
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: nil) { _ in
            m.stop()
        }
        if prefs.startMiningAtLaunch && isConfigured { start() }
        updater.startAutomaticChecks()
    }

    /// A model frozen in the given state, for previews and UI snapshots.
    public init(previewConfig: MinerConfig, status: MinerStatus = MinerStatus(), isRunning: Bool = false,
                log: [String] = [], foundBlocks: [FoundBlock] = [], history: [HashrateSample] = [],
                updater: Updater? = nil, poolAccount: PoolAccount? = nil,
                earnings: Earnings.Summary? = nil, poolOverviews: [String: PoolOverview] = [:],
                poolRecords: [PoolRecord] = []) {
        isLive = false
        self.poolRecords = poolRecords
        self.earnings = earnings
        earningsChecked = true
        self.poolOverviews = poolOverviews
        poolOverviewsUpdated = poolOverviews.isEmpty ? nil : Date().addingTimeInterval(-60)
        self.updater = updater ?? Updater(isLive: false)
        self.poolAccount = poolAccount
        poolAccountUpdated = poolAccount.map { _ in Date().addingTimeInterval(-90) }
        self.history = history
        config = previewConfig
        prefs = AppPreferences()
        self.status = status
        self.isRunning = isRunning
        if isRunning { runningConfig = previewConfig }
        self.log = log.enumerated().map { LogLine(id: $0.offset, text: $0.element) }
        self.foundBlocks = foundBlocks
        launchAtLogin = false
    }

    /// True only the first time it is called after installing (opens the welcome).
    func consumeFirstLaunch() -> Bool {
        guard isLive else { return false }
        let d = UserDefaults.standard
        guard !d.bool(forKey: Keys.welcomed) else { return false }
        d.set(true, forKey: Keys.welcomed)
        return true
    }

    /// What the Keychain currently holds, to avoid rewriting it on every keystroke.
    private var keychainPassword: String?

    private enum Keys {
        static let config = "minerConfig"
        static let prefs = "appPreferences"
        static let rpcPassword = "rpcPassword"
        static let welcomed = "welcomed"
        static let openAtLogin = "openAtLogin"
        static let loginItemVersion = "loginItemVersion"
        static let poolRecords = "poolRecords"
        static let poolsDiscoveredFor = "poolsDiscoveredFor"
    }

    /// Settings go to UserDefaults; the RPC password goes to the Keychain only.
    private func save() {
        guard isLive else { return }
        var stored = config
        stored.node.rpcPassword = ""
        if config.node.rpcPassword != keychainPassword {
            if Keychain.write(Keys.rpcPassword, config.node.rpcPassword) {
                keychainPassword = config.node.rpcPassword
            }
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
        guard isLive, !isRunning, isConfigured else { return }
        isRunning = true
        status = MinerStatus()
        resetNotifications()
        status.state = .starting
        status.mode = config.mode
        requestNotificationPermission()
        runningConfig = config
        miner.start(config)
        startPoolAccountUpdates()
    }

    // MARK: Pool account

    /// The pool mined with, its statistics API and the address it pays: for a DATUM
    /// pool or a pool-hosted gateway that has an API.
    var accountPool: (name: String, website: URL?, api: PoolStatsAPI, address: String)? {
        let c = runningConfig ?? config
        switch c.mode {
        case .datum:
            guard let pool = c.gateway.pool, let api = pool.statsAPI else { return nil }
            return (pool.name, pool.websiteURL, api, c.payoutAddress)
        case .stratum:
            guard let gateway = HostedGateway.find(url: c.stratum.url), let api = gateway.statsAPI else { return nil }
            return (gateway.name, gateway.websiteURL, api, PoolStatsAPI.address(fromUsername: c.stratum.user))
        case .solo:
            return nil
        }
    }

    private static let poolAccountFirstDelay: UInt64 = 30
    private static let poolAccountInterval: UInt64 = 300

    /// Fetches the pool's view of your address 30 s after mining starts, then every 5 min,
    /// and your payouts from the node's wallet every 10 min.
    private func startPoolAccountUpdates() {
        poolAccountTask?.cancel()
        poolAccount = nil
        poolAccountError = nil
        waitingCheckTask?.cancel()
        // A long wait may come with no further status updates; check it on a timer too.
        waitingCheckTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30 * 1_000_000_000)
                guard let self = self, self.isRunning else { continue }
                self.notifyChanges(from: self.status, to: self.status)
            }
        }
        poolAccountTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.poolAccountFirstDelay * 1_000_000_000)
            var tick = 0
            while !Task.isCancelled {
                if self?.accountPool != nil { await self?.refreshPoolAccount() }
                if tick % 2 == 0 { await self?.refreshEarnings() }  // every 10 minutes
                tick += 1
                try? await Task.sleep(nanoseconds: Self.poolAccountInterval * 1_000_000_000)
            }
        }
    }

    /// Pool sizes for a page that shows them, unless fetched in the last 5 minutes.
    func refreshPoolOverviewsIfStale() async {
        if poolOverviewsUpdated.map({ Date().timeIntervalSince($0) > 300 }) ?? true { await refreshPoolOverviews() }
    }

    /// Fetches every built-in pool's size, in parallel.
    func refreshPoolOverviews() async {
        guard isLive else { return }
        let apis: [(String, PoolStatsAPI)] = DatumPool.all.compactMap { p in p.statsAPI.map { (p.id, $0) } }
            + [("b2pool", .b2pool)]
        await withTaskGroup(of: (String, PoolOverview?).self) { group in
            for (id, api) in apis {
                group.addTask { (id, try? await api.overview()) }
            }
            for await (id, overview) in group {
                if let overview = overview { poolOverviews[id] = overview }
            }
        }
        poolOverviewsUpdated = Date()
    }

    /// Reads payouts to the payout address from the node's wallet (off the main thread).
    func refreshEarnings() async {
        guard isLive else { return }
        let node = config.node
        let address = accountPool?.address ?? config.payoutAddress
        guard !address.isEmpty else { return }
        do {
            let summary = try await Task.detached { try Earnings.summary(node: node, address: address) }.value
            // New payouts since the last read of the same address (none on the first read).
            if let old = earnings, earningsAddress == address {
                let known = Set(old.payouts.map(\.txid))
                for p in summary?.payouts ?? [] where !known.contains(p.txid) && p.status != .orphaned {
                    notify("Payout: \(formatAmount(p.amount))",
                           "A mining payout to your address is in your node's wallet. It becomes spendable after \(p.confirmationsNeeded.formatted()) confirmations.",
                           id: "payout-" + p.txid)
                }
            }
            earnings = summary
            earningsAddress = address
            earningsError = nil
        } catch {
            earningsError = "Couldn't read your node's wallet: \(error.localizedDescription)"
        }
        earningsChecked = true
    }

    func refreshPoolAccount() async {
        guard let pool = accountPool else { return }
        do {
            let account = try await pool.api.account(for: pool.address)
            poolAccount = account
            poolAccountUpdated = Date()
            poolAccountError = nil
            record(pool.api, pool.address, account, mining: isRunning)
        } catch {
            poolAccountError = "Couldn't reach \(pool.name)'s statistics: \(error.localizedDescription)"
        }
    }

    /// Finds the built-in pools that know your payout address, once per address:
    /// pools you aren't mining with are only asked again when you ask (`refresh(_:)`).
    func discoverPools() async {
        guard isLive else { return }
        let address = accountPool?.address ?? config.payoutAddress.trimmingCharacters(in: .whitespaces)
        let d = UserDefaults.standard
        guard !address.isEmpty, d.string(forKey: Keys.poolsDiscoveredFor) != address else { return }
        d.set(address, forKey: Keys.poolsDiscoveredFor)
        let current = accountPool?.api
        let apis = [PoolStatsAPI.lazarus, .omega, .riptide, .b2pool]
            .filter { api in api != current && !poolRecords.contains { $0.api == api && $0.address == address } }
        await withTaskGroup(of: (PoolStatsAPI, PoolAccount?).self) { group in
            for api in apis { group.addTask { (api, try? await api.account(for: address)) } }
            for await (api, account) in group {
                if let account = account, !account.unknown { record(api, address, account, mining: false) }
            }
        }
    }

    /// Asks one pool you aren't mining with for its latest report on your address.
    func refresh(_ r: PoolRecord) async {
        guard isLive, let account = try? await r.api.account(for: r.address) else { return }
        record(r.api, r.address, account, mining: false)
    }

    private func record(_ api: PoolStatsAPI, _ address: String, _ account: PoolAccount, mining: Bool) {
        var r = poolRecords.first { $0.api == api && $0.address == address } ?? PoolRecord(api: api, address: address)
        r.account = account
        r.updated = Date()
        if mining { r.lastMined = Date() }
        poolRecords.removeAll { $0.id == r.id }
        poolRecords.append(r)
        poolRecords.sort { ($0.lastMined ?? .distantPast) > ($1.lastMined ?? .distantPast) }
        if let data = try? JSONEncoder().encode(poolRecords) { UserDefaults.standard.set(data, forKey: Keys.poolRecords) }
    }

    /// The settings the current mining session started with.
    @Published private(set) var runningConfig: MinerConfig?

    /// Settings changed since mining started; they apply on restart.
    var hasPendingChanges: Bool { isRunning && runningConfig.map { $0 != config } ?? false }

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
        poolAccountTask?.cancel()
        waitingCheckTask?.cancel()
        isRunning = false
        runningConfig = nil
        status.state = .stopped
        status.hashrate = 0
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            append(log: "Could not change Open at Login: \(error.localizedDescription)")
        }
        UserDefaults.standard.set(on, forKey: Keys.openAtLogin)
        UserDefaults.standard.set(Miner.version, forKey: Keys.loginItemVersion)
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    /// Each release is signed anew, and macOS can then quietly stop opening the app
    /// at login. So after an update, a wanted login item is registered again.
    /// Returns whether the app opens at login.
    private static func refreshLoginItem() -> Bool {
        let d = UserDefaults.standard
        let service = SMAppService.mainApp
        let wanted = d.object(forKey: Keys.openAtLogin) as? Bool
            ?? (service.status == .enabled || service.status == .requiresApproval)
        if wanted && d.string(forKey: Keys.loginItemVersion) != Miner.version {
            try? service.unregister()
            try? service.register()
            d.set(true, forKey: Keys.openAtLogin)
            d.set(Miner.version, forKey: Keys.loginItemVersion)
        }
        return service.status == .enabled
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
        notifyChanges(from: status, to: s)
        status = s
        recordHistory(s)
        if s.state == .mining, Date().timeIntervalSince(lastRateLog) >= Self.rateLogInterval {
            lastRateLog = Date()
            var line = "Hashrate \(formatHashrate(s.hashrate)), average \(formatHashrate(s.averageHashrate))"
            if s.gpuName != nil { line += " (CPU \(formatHashrate(s.cpuHashrate)), GPU \(formatHashrate(s.gpuHashrate)))" }
            if let e = s.expectedSecondsPerBlock { line += ", expected time per block ≈ \(formatDuration(e))" }
            if s.mode != .solo { line += ", " + s.shareLogSummary }
            append(log: line)
        }
    }

    private func recordHistory(_ s: MinerStatus) {
        let now = Date()
        guard s.state == .mining, now.timeIntervalSince(history.last?.time ?? .distantPast) >= Self.historyInterval else { return }
        history.append(HashrateSample(time: now, hashrate: s.hashrate))
        history.removeAll { now.timeIntervalSince($0.time) > Self.historyWindow }
    }

    /// The dashboard chart covers the last hour at 10-second resolution.
    private static let historyInterval: TimeInterval = 10
    private static let historyWindow: TimeInterval = 3600

    private var lastRateLog = Date()
    private var nextLogID = 0
    /// Lines shown in the Log window (the log file keeps everything).
    private static let logLinesKept = 1000
    /// How often the hashrate is written to the log while mining.
    private static let rateLogInterval: TimeInterval = 600

    fileprivate func found(_ block: FoundBlock) {
        do {
            try FoundBlocks.append(block)
        } catch {
            append(log: "Could not save the solved block to \(FoundBlocks.file.path): \(error.localizedDescription). Block \(block.hash), hex: \(block.blockHex ?? "none")")
        }
        foundBlocks = FoundBlocks.all()
        notify(block.isAccepted ? "Block found! 🎉" : "Block solved but not accepted",
               "Height \(block.height): \(block.result)\n\(block.hash)", id: block.hash)
    }

    // MARK: Notifications

    /// What was already notified in this mining session, so each alert comes once.
    private var notified: Set<String> = []
    /// When mining started waiting, and the pool's rejections since its last acceptance.
    private var waitingSince: Date?
    private var rejectsInARow = 0

    /// After this long without work, "waiting" becomes worth a notification.
    private static let waitingAlertDelay: TimeInterval = 300
    /// Rejected shares in a row before a notification.
    private static let rejectAlertCount = 5

    private func resetNotifications() {
        notified = []
        waitingSince = nil
        rejectsInARow = 0
    }

    /// Notifies about the events worth leaving the app for: the pool's first accepted
    /// share, a run of rejected shares, a long wait for work, an outdated node.
    private func notifyChanges(from old: MinerStatus, to s: MinerStatus) {
        let pool = s.poolName ?? "The pool"
        if s.mode != .solo, s.confirmedShares > old.confirmedShares {
            rejectsInARow = 0
            notifyOnce("first-share", "First share accepted",
                       "\(pool) accepted your first share this session. Your Mac is mining with the pool.")
        }
        let rejected = s.poolRejected + s.sharesRejected, wasRejected = old.poolRejected + old.sharesRejected
        if rejected > wasRejected {
            rejectsInARow += rejected - wasRejected
            if rejectsInARow >= Self.rejectAlertCount {
                notifyOnce("rejects", "\(pool) is rejecting your shares",
                           s.poolRejectReason ?? "\(rejectsInARow) shares in a row were rejected. Open BLAKE2b Miner for details.")
            }
        }
        if case .waiting(let reason) = s.state, !reason.hasPrefix("Paused") {
            let since = waitingSince ?? Date()
            waitingSince = since
            if Date().timeIntervalSince(since) >= Self.waitingAlertDelay {
                notifyOnce("waiting", "Mining has stopped for 5 minutes", reason)
            }
        } else if s.state == .mining {
            waitingSince = nil
            notified.remove("waiting")  // a later outage is notified again
        }
        if let warning = s.nodeWarning {
            notifyOnce("node-outdated", "Your node needs an update", warning)
        }
    }

    private func notifyOnce(_ key: String, _ title: String, _ body: String) {
        guard notified.insert(key).inserted else { return }
        notify(title, body, id: key)
    }

    private func notify(_ title: String, _ body: String, id: String) {
        guard isLive else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
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

/// Receives callbacks on the miner's threads and forwards them to the main actor,
/// in order (the main queue is FIFO; separate Tasks are not guaranteed to be).
private final class Bridge: MinerDelegate {
    weak var model: AppModel?

    private func onMain(_ body: @escaping @MainActor (AppModel) -> Void) {
        DispatchQueue.main.async { [weak model] in
            MainActor.assumeIsolated { if let model = model { body(model) } }
        }
    }

    func miner(log line: String) { onMain { $0.append(log: line) } }
    func miner(status: MinerStatus) { onMain { $0.update(status) } }
    func miner(found block: FoundBlock) { onMain { $0.found(block) } }
}

/// One point of the dashboard's hashrate chart.
public struct HashrateSample: Identifiable {
    public let time: Date
    public let hashrate: Double
    public var id: Date { time }

    public init(time: Date, hashrate: Double) {
        self.time = time
        self.hashrate = hashrate
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
        try? FoundBlocks.appendData(data, to: url)
    }
}

/// A pool that knows your address, and what it last reported.
public struct PoolRecord: Codable, Identifiable, Equatable {
    public let api: PoolStatsAPI
    public let address: String
    public var account: PoolAccount?
    public var updated: Date?
    /// When you last mined there with this app (nil: found by asking the pool).
    public var lastMined: Date?

    public var id: String { api.rawValue + ":" + address }

    public init(api: PoolStatsAPI, address: String) {
        self.api = api
        self.address = address
    }
}
