// Renders the app's screens in representative states to PNG files, for
// reviewing the UI without running the miner: scripts/ui-snapshots.sh
import AppKit
import MinerCore
import MinerUI
import SwiftUI

let outDir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "ui-snapshots")
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)

@MainActor
func render<V: View>(_ name: String, width: CGFloat? = nil, height: CGFloat? = nil, dark: Bool = false, _ view: V) {
    let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    let host = NSHostingView(rootView: view.background(Color(nsColor: .windowBackgroundColor)))
    host.appearance = appearance
    let fitting = host.fittingSize
    host.frame = CGRect(x: 0, y: 0, width: width ?? fitting.width, height: height ?? fitting.height)
    let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.appearance = appearance
    window.contentView = host
    host.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.4))
    if height == nil, host.fittingSize.height != host.frame.height {  // content settled to a different size
        host.frame.size.height = host.fittingSize.height
        window.setContentSize(host.frame.size)
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
    }
    guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
    host.cacheDisplay(in: host.bounds, to: rep)
    let file = outDir.appendingPathComponent(name + (dark ? "-dark" : "") + ".png")
    try? rep.representation(using: .png, properties: [:])?.write(to: file)
    print(file.path)
}

// MARK: Sample states

func config(_ mode: MiningMode, address: String = "bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4") -> MinerConfig {
    var c = MinerConfig()
    c.mode = mode
    c.payoutAddress = address
    c.threads = 12
    return c
}

func status(_ mode: MiningMode, state: MinerState = .mining, rate: Double = 155_300_000) -> MinerStatus {
    var s = MinerStatus()
    s.state = state
    s.mode = mode
    s.hashrate = rate
    s.averageHashrate = rate * 0.97
    s.threads = 12
    s.startedAt = Date().addingTimeInterval(-5_400)
    s.totalHashes = UInt64(rate * 0.97 * 5_400)
    switch mode {
    case .solo:
        s.height = 975_302
        s.networkDifficulty = 4_625_039_957
        s.expectedSecondsPerBlock = 4_625_039_957 * hashesPerDifficulty / rate
        s.transactions = 412
        s.reward = 3.1297
    case .datum, .stratum:
        s.shareDifficulty = 1_024
        s.sharesAccepted = 3
        s.gatewayStatus = mode == .datum ? "Pooled with Lazarus · your node builds the blocks" : nil
        if mode == .datum {
            s.poolName = "Lazarus"
            s.poolConfirmed = 3
        }
    }
    return s
}

let sampleLog = [
    "2026-10-03 13:09:45  Started 12 CPU hashing threads (your own DATUM Gateway; NEON + SHA3 assembly kernel)",
    "2026-10-03 13:09:45  Started your DATUM Gateway (Stratum on port 23334); pooled mining with Lazarus, your node builds the blocks",
    "2026-10-03 13:09:46  [gateway] DATUM Server MOTD: RATUM Prime",
    "2026-10-03 13:09:47  Subscribed (extranonce1 b10cf00d, extranonce2 8 bytes)",
    "2026-10-03 13:09:47  Authorized as bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4",
    "2026-10-03 13:19:47  Hashrate 155.3 MH/s, average 150.6 MH/s",
    "2026-10-03 13:21:15  [gateway] New network block 975302",
    "2026-10-03 13:24:02  Share accepted by your gateway, sent to Lazarus (difficulty 1,024)",
    "2026-10-03 13:24:03  [gateway] Lazarus accepted your share",
    "2026-10-03 13:29:40  Hashrate 155.1 MH/s, average 150.7 MH/s, shares 1 accepted by the pool",
    "2026-10-03 13:31:10  Problem: Can't reach Bitcoin Knots at 127.0.0.1:8332. Is it running, with its RPC server turned on (server=1)?",
]

@MainActor
func scenes(dark: Bool) {
    func menu(_ name: String, _ model: AppModel) {
        render("menu-" + name, width: 300, dark: dark, MenuView().environmentObject(model))
    }
    menu("unconfigured", AppModel(previewConfig: config(.datum, address: "")))
    menu("ready", AppModel(previewConfig: config(.datum)))
    var found = status(.solo)
    found.blocksFound = 1
    menu("mining-solo-found", AppModel(previewConfig: config(.solo), status: found, isRunning: true))
    menu("mining-datum", AppModel(previewConfig: config(.datum), status: status(.datum), isRunning: true))
    menu("mining-solo", AppModel(previewConfig: config(.solo), status: status(.solo), isRunning: true))
    menu("mining-hosted", AppModel(previewConfig: config(.stratum), status: status(.stratum), isRunning: true))
    menu("waiting", AppModel(previewConfig: config(.datum),
                             status: status(.datum, state: .waiting("Can't reach Bitcoin Knots at 127.0.0.1:8332. Is it running, with its RPC server turned on (server=1)? [Could not connect to the server.]"), rate: 0),
                             isRunning: true))
    // A realistic last hour of hashrate for the chart.
    let now = Date()
    let history = (0..<360).map { i -> HashrateSample in
        let t = Double(i)
        let rate = 152e6 + 4e6 * sin(t / 9) + 2e6 * sin(t / 2.3) - (i > 200 && i < 215 ? 40e6 : 0)
        return HashrateSample(time: now.addingTimeInterval(-3600 + t * 10), hashrate: rate)
    }
    func window(_ name: String, _ model: AppModel, width: CGFloat = 1040, height: CGFloat = 720) {
        render("window-" + name, width: width, height: height, dark: dark, MainWindowView().environmentObject(model))
    }
    // Sample payouts (one a few days apart, the newest still maturing) and pool sizes.
    let payouts = (0..<6).map { i in
        Earnings.Payout(txid: String(repeating: String(i), count: 64), time: now.addingTimeInterval(Double(-i) * 4 * 86400),
                        amount: 0.00000412 + Double(i % 3) * 0.0000013, confirmations: 30 + i * 550,
                        status: i < 2 ? .maturing : .spendable)
    }
    let overviews = ["lazarus": PoolOverview(networkShare: 0.214, miners: 184), 
                     "riptide": PoolOverview(networkShare: 0.037, miners: 41, blocks7d: 37),
                     "b2pool": PoolOverview(networkShare: 0.055, miners: 166)]
    // You mine with Lazarus (the default config's pool); Omega, retired, is shown as a
    // pool you left: it didn't pay this small a miner.
    var lazarusAccount = PoolAccount()
    lazarusAccount.online = true
    lazarusAccount.hashrate = 0.98e9
    lazarusAccount.shares = 6
    lazarusAccount.sharesPeriod = "in the payout window (about the last 5 h)"
    lazarusAccount.carried = 0.00001108
    lazarusAccount.minimumPayout = 0.005
    lazarusAccount.paid = 0
    var omegaAccount = PoolAccount()
    omegaAccount.windowPercent = 0.0000176
    omegaAccount.nextBlockPayout = 0
    omegaAccount.notice = "Your part of a block is under Omega's 546-sat minimum, so Omega pays it to the other miners. Nothing is carried over: at this hashrate, mining here earns nothing."
    var omegaRecord = PoolRecord(api: .omega, address: "bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4")
    omegaRecord.account = omegaAccount
    omegaRecord.updated = now.addingTimeInterval(-2 * 3600)
    omegaRecord.lastMined = now.addingTimeInterval(-3 * 3600)
    for page in Page.allCases {
        var c = config(.datum)
        let model = AppModel(previewConfig: c, status: status(.datum), isRunning: true, log: sampleLog,
                             history: history, poolAccount: page == .earnings ? lazarusAccount : nil,
                             earnings: Earnings.Summary(wallet: "Main", payouts: payouts),
                             poolOverviews: overviews, poolRecords: [omegaRecord])
        model.page = page
        window(page.rawValue, model, height: page == .earnings ? 1500 : 720)
    }
    window("overview-fullscreen", AppModel(previewConfig: config(.datum), status: status(.datum), isRunning: true,
                                           log: sampleLog, history: history), width: 1728, height: 1080)
    window("overview-solo", AppModel(previewConfig: config(.solo), status: status(.solo), isRunning: true,
                                     log: sampleLog, history: history))
    window("overview-welcome", AppModel(previewConfig: config(.datum, address: "")))
    // GPU mining on: the Performance settings and the dashboard's CPU/GPU split.
    var gpuConfig = config(.datum)
    gpuConfig.threads = 12
    gpuConfig.useGPU = true
    var gpuStatus = status(.datum, rate: 998e6)
    gpuStatus.threads = 12
    gpuStatus.cpuHashrate = 240e6
    gpuStatus.gpuHashrate = 758e6
    gpuStatus.gpuName = "Apple M4 Pro"
    let gpuHistory = history.map { HashrateSample(time: $0.time, hashrate: $0.hashrate * 6.5) }
    var account = PoolAccount()
    account.online = true
    account.hashrate = 968e6
    account.shares = 14
    account.sharesPeriod = "in the window"
    account.windowPercent = 0.0123
    account.nextBlockPayout = 0.00038
    account.perDay = 0.00081
    account.unpaid = 0.00012
    account.immature = 0.00038
    account.paid = 0
    window("overview-gpu", AppModel(previewConfig: gpuConfig, status: gpuStatus, isRunning: true, log: sampleLog,
                                    history: gpuHistory, poolAccount: account), height: 1100)
    let gpuSettings = AppModel(previewConfig: gpuConfig, status: gpuStatus, isRunning: true)
    gpuSettings.page = .performance
    window("performance-gpu", gpuSettings)
    menu("mining-gpu", AppModel(previewConfig: gpuConfig, status: gpuStatus, isRunning: true))
    // A pool that is no longer built in, kept as a custom pool.
    var retired = config(.datum)
    retired.gateway = (try? JSONDecoder().decode(GatewaySettings.self, from: Data(#"{"poolID":"dxpool"}"#.utf8))) ?? retired.gateway
    let retiredModel = AppModel(previewConfig: retired)
    retiredModel.page = .mining
    window("mining-retired-pool", retiredModel)
    // An update on offer.
    let release = UpdateCheck.Release(version: "1.9.0", notes: "", page: URL(string: "https://github.com/taimouralneimat/blake2b-miner/releases")!,
                                      zip: nil, checksums: nil)
    let updating = AppModel(previewConfig: config(.datum), status: status(.datum), isRunning: true, log: sampleLog,
                            history: history, updater: Updater(preview: .available(release)))
    window("overview-update", updating)
    menu("mining-update", updating)
    let hosted = AppModel(previewConfig: config(.stratum))
    hosted.page = .mining
    window("mining-hosted", hosted)
}

MainActor.assumeIsolated {
    scenes(dark: false)
    scenes(dark: true)
}
