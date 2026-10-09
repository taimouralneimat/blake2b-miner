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

func config(_ mode: MiningMode, address: String = "bc1qexampleaddressxxxxxxxxxxxxxxxxxxxxxxx0") -> MinerConfig {
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
        s.shareDifficulty = 16_384
        s.sharesAccepted = 3
        s.gatewayStatus = mode == .datum ? "Pooled with DXPool · your node builds the blocks" : nil
    }
    return s
}

let sampleLog = [
    "2026-10-03 13:09:45  Started 12 CPU hashing threads (your own DATUM Gateway; NEON + SHA3 assembly kernel)",
    "2026-10-03 13:09:45  Started your DATUM Gateway (Stratum on port 23334); pooled mining with DXPool, your node builds the blocks",
    "2026-10-03 13:09:46  [gateway] DATUM Server MOTD: RATUM Prime",
    "2026-10-03 13:09:47  Subscribed (extranonce1 b10cf00d, extranonce2 8 bytes)",
    "2026-10-03 13:09:47  Authorized as bc1qexampleaddressxxxxxxxxxxxxxxxxxxxxxxx0",
    "2026-10-03 13:19:47  Hashrate 155.3 MH/s, average 150.6 MH/s",
    "2026-10-03 13:21:15  [gateway] New network block 975302",
    "2026-10-03 13:24:02  Share accepted (difficulty 16,384)",
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
    for page in Page.allCases {
        let model = AppModel(previewConfig: config(.datum), status: status(.datum), isRunning: true, log: sampleLog,
                             history: history)
        model.page = page
        window(page.rawValue, model)
    }
    window("overview-fullscreen", AppModel(previewConfig: config(.datum), status: status(.datum), isRunning: true,
                                           log: sampleLog, history: history), width: 1728, height: 1080)
    window("overview-solo", AppModel(previewConfig: config(.solo), status: status(.solo), isRunning: true,
                                     log: sampleLog, history: history))
    window("overview-welcome", AppModel(previewConfig: config(.datum, address: "")))
    // GPU mining on: the Performance settings and the dashboard's CPU/GPU split.
    var gpuConfig = config(.datum)
    gpuConfig.threads = 10
    gpuConfig.useGPU = true
    var gpuStatus = status(.datum, rate: 998e6)
    gpuStatus.threads = 10
    gpuStatus.cpuHashrate = 240e6
    gpuStatus.gpuHashrate = 758e6
    gpuStatus.gpuName = "Apple M4 Pro"
    gpuStatus.gpuLoad = 100
    let gpuHistory = history.map { HashrateSample(time: $0.time, hashrate: $0.hashrate * 6.5) }
    window("overview-gpu", AppModel(previewConfig: gpuConfig, status: gpuStatus, isRunning: true, log: sampleLog,
                                    history: gpuHistory))
    let gpuSettings = AppModel(previewConfig: gpuConfig, status: gpuStatus, isRunning: true)
    gpuSettings.page = .performance
    window("performance-gpu", gpuSettings)
    menu("mining-gpu", AppModel(previewConfig: gpuConfig, status: gpuStatus, isRunning: true))
    let hosted = AppModel(previewConfig: config(.stratum))
    hosted.page = .mining
    window("mining-hosted", hosted)
}

MainActor.assumeIsolated {
    scenes(dark: false)
    scenes(dark: true)
}
