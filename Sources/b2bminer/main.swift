import Foundation
import MinerCore

let usage = """
b2bminer \(Miner.version) - BLAKE2b miner for the Bitcoin Knots header-v2 chain

USAGE
  b2bminer datum --address <addr> [--pool <id>|none] [datum options] [node options] [cpu options]
      Recommended. Runs your own DATUM Gateway (bundled) next to your Knots
      node: your node builds the blocks, pooled through a DATUM pool or solo.
  b2bminer solo --address <addr> [node options] [cpu options]
      Solo mine with templates straight from your local Bitcoin Knots node.
  b2bminer stratum --url <host:port> --user <name> [--password <pw>] [cpu options]
      Mine to a Stratum server: a DATUM Gateway or a pool's public gateway.
      Use stratum+ssl://host:port for TLS.
  b2bminer probe --url <host:port> --user <name>
      Check that a Stratum server or pool works with this miner, without mining.
  b2bminer pools
      List DATUM pools (for `datum --pool`) and pool-hosted gateways.
  b2bminer check [--address <addr>] [--pool <id>] [node options]
      Check your node: reachable, synced, BLAKE2b templates, payout address,
      and blockmaxweight for pooled DATUM.
  b2bminer selftest [--node] [node options]
      Verify the hashing against the official Knots test vectors (and, with
      --node, against recent blocks from your node).
  b2bminer bench [--threads N] [--gpu] [--no-cpu] [--gpu-load P] [--low-priority] [--seconds S]
      Measure the hashrate of this Mac (CPU threads, the GPU, or both).

NODE OPTIONS
  --host <ip>            RPC host (default 127.0.0.1)
  --port <n>             RPC port (default 8332)
  --datadir <path>       Knots data directory holding .cookie
                         (default ~/Library/Application Support/Bitcoin)
  --rpcuser <u>          use instead of the cookie, with the password in the
                         B2B_RPC_PASSWORD environment variable (or --rpcpassword,
                         which other users can see in `ps`)
  --tag <text>           text in your coinbase (default "/BLAKE2b Miner/")

DATUM OPTIONS
  --pool <id>            DATUM pool to join, or "none" for solo (default: none)
  --stratum-port <n>     port your gateway serves miners on (default 23334)
  --allow-network        let other miners on your network use your gateway
  --pool-only            stop mining while the pool is unreachable
                         (default: keep mining solo, blocks pay you 100%)

CPU AND GPU OPTIONS
  --threads <n>          CPU hashing threads (default: all \(CPUInfo.cores) cores)
  --no-cpu               don't mine with the CPU (use with --gpu)
  --gpu                  also mine with the GPU (Metal)
  --gpu-load <percent>   share of the GPU's time to use, 10-100 (default 100)
  --low-priority         keep the Mac responsive: CPU threads at low priority
                         (mostly on efficiency cores, up to half the CPU
                         hashrate) and the GPU in short bursts (~10% less)
  --no-battery-pause     keep mining on battery power
"""

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n\n".utf8))
    exit(2)
}

var args = Array(CommandLine.arguments.dropFirst())
guard let command = args.first else { print(usage); exit(0) }
args.removeFirst()

var options: [String: String] = [:]
var flags = Set<String>()
var i = 0
while i < args.count {
    let a = args[i]
    guard a.hasPrefix("--") else { fail("unexpected argument \(a)") }
    let key = String(a.dropFirst(2))
    if ["node", "low-priority", "no-battery-pause", "help", "allow-network", "pool-only", "gpu", "no-cpu"].contains(key) {
        flags.insert(key)
        i += 1
    } else {
        guard i + 1 < args.count else { fail("\(a) needs a value") }
        options[key] = args[i + 1]
        i += 2
    }
}
if flags.contains("help") || ["-h", "help", "--help"].contains(command) { print(usage); exit(0) }

let knownOptions: Set<String> = ["address", "pool", "stratum-port", "url", "user", "password", "threads", "seconds", "gpu-load",
                                 "host", "port", "datadir", "rpcuser", "rpcpassword", "tag"]
if let unknown = options.keys.first(where: { !knownOptions.contains($0) }) {
    fail("unknown option --\(unknown) (see b2bminer --help)")
}

func intOption(_ key: String) -> Int? {
    guard let v = options[key] else { return nil }
    guard let n = Int(v) else { fail("--\(key) must be a number") }
    return n
}

func portOption(_ key: String) -> Int? {
    guard let n = intOption(key) else { return nil }
    guard (1...65535).contains(n) else { fail("--\(key) must be a port number from 1 to 65535") }
    return n
}

/// --pool as a DATUM pool id, "" for solo ("none" or not given).
func poolOption() -> String {
    let id = options["pool"] ?? "none"
    if id == "none" { return "" }
    guard DatumPool.find(id) != nil else {
        fail("unknown DATUM pool \(id); choose one of: \(DatumPool.all.map(\.id).joined(separator: ", ")), none")
    }
    return id
}

func nodeConfig() -> NodeConfig {
    var n = NodeConfig()
    if let h = options["host"] { n.host = h }
    if let p = portOption("port") { n.port = p }
    if let d = options["datadir"] { n.dataDir = d }
    if let u = options["rpcuser"] { n.rpcUser = u }
    // Prefer B2B_RPC_PASSWORD: a password on the command line is visible to other users in `ps`.
    if let p = options["rpcpassword"] ?? ProcessInfo.processInfo.environment["B2B_RPC_PASSWORD"] { n.rpcPassword = p }
    return n
}

final class ConsoleDelegate: MinerDelegate {
    let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()
    var lastReport = Date()

    func miner(log line: String) { print("\(formatter.string(from: Date())) \(line)"); fflush(stdout) }

    func miner(status s: MinerStatus) {
        guard Date().timeIntervalSince(lastReport) >= 60, s.state == .mining else { return }
        lastReport = Date()
        var line = "Hashrate \(formatHashrate(s.hashrate)) (average \(formatHashrate(s.averageHashrate)))"
        if s.gpuName != nil { line += " | CPU \(formatHashrate(s.cpuHashrate)), GPU \(formatHashrate(s.gpuHashrate))" }
        if let e = s.expectedSecondsPerBlock { line += " | expected time per block: \(formatDuration(e))" }
        if s.mode != .solo { line += " | " + s.shareLogSummary }
        miner(log: line)
    }

    func miner(found block: FoundBlock) {
        do {
            try FoundBlocks.append(block)
        } catch {
            miner(log: "Could not save the solved block to \(FoundBlocks.file.path): \(error.localizedDescription). Block \(block.hash), hex: \(block.blockHex ?? "none")")
        }
    }
}

func runMiner(_ config: MinerConfig) -> Never {
    let miner = Miner()
    let delegate = ConsoleDelegate()
    miner.delegate = delegate
    signal(SIGINT, SIG_IGN)
    signal(SIGTERM, SIG_IGN)
    let sources = [SIGINT, SIGTERM].map { sig -> DispatchSourceSignal in
        let s = DispatchSource.makeSignalSource(signal: sig, queue: .global())
        s.setEventHandler {
            miner.stop()
            exit(0)
        }
        s.resume()
        return s
    }
    _ = sources
    miner.start(config)
    dispatchMain()
}

/// --gpu-load, which only makes sense with --gpu.
func gpuLoadOption() -> Int? {
    guard let load = intOption("gpu-load") else { return nil }
    guard flags.contains("gpu") else { fail("--gpu-load needs --gpu") }
    guard (10...100).contains(load) else { fail("--gpu-load must be from 10 to 100") }
    return load
}

func cpuConfig(_ c: inout MinerConfig) {
    if let t = intOption("threads") {
        guard (1...Engine.maxThreads).contains(t) else { fail("--threads must be from 1 to \(Engine.maxThreads)") }
        c.threads = t
    }
    c.useCPU = !flags.contains("no-cpu")
    c.useGPU = flags.contains("gpu")
    if let load = gpuLoadOption() { c.gpuLoad = load }
    guard c.useCPU || c.useGPU else { fail("--no-cpu needs --gpu") }
    c.lowPriority = flags.contains("low-priority")
    c.pauseOnBattery = !flags.contains("no-battery-pause")
}

switch command {
case "datum":
    var c = MinerConfig()
    c.mode = .datum
    c.node = nodeConfig()
    guard let address = options["address"] else { fail("datum mining needs --address <your payout address>") }
    c.payoutAddress = address
    c.gateway.poolID = poolOption()
    if let p = portOption("stratum-port") { c.gateway.stratumPort = p }
    c.gateway.allowNetworkMiners = flags.contains("allow-network")
    c.gateway.soloWhenPoolDown = !flags.contains("pool-only")
    cpuConfig(&c)
    runMiner(c)

case "solo":
    var c = MinerConfig()
    c.mode = .solo
    c.node = nodeConfig()
    guard let address = options["address"] else { fail("solo mining needs --address <your payout address>") }
    c.payoutAddress = address
    if let tag = options["tag"] { c.coinbaseTag = tag }
    cpuConfig(&c)
    runMiner(c)

case "stratum":
    var c = MinerConfig()
    c.mode = .stratum
    guard let url = options["url"] else { fail("stratum needs --url <host:port>") }
    guard let user = options["user"] else { fail("stratum needs --user <name>") }
    c.stratum.url = url
    c.stratum.user = user
    if let p = options["password"] { c.stratum.password = p }
    cpuConfig(&c)
    runMiner(c)

case "probe":
    var c = StratumConfig()
    guard let url = options["url"] else { fail("probe needs --url <host:port>") }
    c.url = url
    c.user = options["user"] ?? "probe"
    if let p = options["password"] { c.password = p }
    let report = StratumProbe.run(c)
    report.lines.forEach { print($0) }
    print(report.compatible ? "Compatible: this server works with b2bminer." : "NOT compatible or not reachable.")
    exit(report.compatible ? 0 : 1)

case "pools":
    print("DATUM pools: your own gateway, your node builds the blocks (b2bminer datum --pool <id>)\n")
    for p in DatumPool.all {
        print("  \(p.id): \(p.name), \(p.host):\(p.port), fee \(p.fee), \(p.website)")
    }
    print("\nPool-hosted gateways: the pool builds the blocks (b2bminer stratum --url <url>)\n")
    for p in HostedGateway.all {
        print("\(p.name)\n  \(p.url)\n  fee: \(p.fee) · \(p.website)\n  \(p.note)\n")
    }
    print("Mine with: b2bminer stratum --url <url> --user <your address>[.worker]")

case "check":
    var c = MinerConfig()
    c.node = nodeConfig()
    c.payoutAddress = options["address"] ?? ""
    c.mode = .datum
    c.gateway.poolID = poolOption()
    let lines = NodeCheck.run(c)
    lines.forEach { print($0) }
    exit(lines.contains { $0.hasPrefix("❌") } ? 1 : 0)

case "selftest":
    var allPassed = true
    _ = SelfTest.run(node: flags.contains("node") ? nodeConfig() : nil) { r in
        print("\(r.passed ? "PASS" : "FAIL")  \(r.name): \(r.detail)")
        allPassed = allPassed && r.passed
    }
    print(allPassed ? "All checks passed." : "SOME CHECKS FAILED.")
    exit(allPassed ? 0 : 1)

case "bench":
    let useCPU = !flags.contains("no-cpu"), useGPU = flags.contains("gpu")
    guard useCPU || useGPU else { fail("--no-cpu needs --gpu") }
    let gpuLoad = gpuLoadOption() ?? 100
    let threads = useCPU ? intOption("threads") ?? CPUInfo.cores : 0
    let seconds = Double(intOption("seconds") ?? 10)
    guard seconds >= 1, !useCPU || (1...Engine.maxThreads).contains(threads) else {
        fail("--threads must be from 1 to \(Engine.maxThreads) and --seconds at least 1")
    }
    var gpuName = ""
    do {
        let responsive = flags.contains("low-priority")
        if useCPU { try Engine.start(threads: threads, lowPriority: responsive) }
        if useGPU { gpuName = try Engine.startGPU(load: gpuLoad, responsive: responsive) }
    } catch { Engine.stop(); fail(error.localizedDescription) }
    Engine.setWork(jobID: 1, input: Data(count: 80), target: UInt256(words: [0, 0, 0, 0]))
    Thread.sleep(forTimeInterval: 1)
    let cpu0 = Engine.cpuHashes, gpu0 = Engine.gpuHashes
    let t0 = Date()
    Thread.sleep(forTimeInterval: seconds)
    let dt = Date().timeIntervalSince(t0)
    let cpuRate = Double(Engine.cpuHashes - cpu0) / dt, gpuRate = Double(Engine.gpuHashes - gpu0) / dt
    Engine.stop()
    var parts = [String]()
    if useCPU { parts.append("CPU \(threads) threads: \(formatHashrate(cpuRate)) (\(Engine.kernel) kernel)") }
    if useGPU { parts.append("GPU \(gpuName): \(formatHashrate(gpuRate))") }
    if useCPU && useGPU { parts.append("total: \(formatHashrate(cpuRate + gpuRate))") }
    print(parts.joined(separator: "\n"))

default:
    fail("unknown command \(command)\n\n\(usage)")
}
