import Foundation

/// Mines through the bundled DATUM Gateway: runs the gateway next to the
/// user's node (which builds the blocks) and takes work from its Stratum port.
final class GatewaySource: WorkSource {
    weak var miner: Miner? {
        didSet { stratum.miner = miner }
    }

    private let config: MinerConfig
    private let rpc: NodeRPC
    private var chain = "?"
    /// Blocks the gateway solved, waiting to be looked up in the node: (hash, reported at).
    private var pendingBlocks: [(hash: String, at: Date)] = []
    private var seenBlocks = Set<String>()
    private let gateway: DatumGatewayProcess
    private let stratum: StratumSource
    private var lastStart: Date?
    private var readyAt = Date.distantFuture

    /// Time for the gateway to fetch a template and open its Stratum port.
    private static let warmup: TimeInterval = 3
    /// A gateway that exits sooner than this after starting is not restarted
    /// right away; the miner's normal retry delay applies instead.
    private static let minimumUptime: TimeInterval = 10

    init(config: MinerConfig) {
        self.config = config
        rpc = NodeRPC(config.node, timeout: 10)
        gateway = DatumGatewayProcess(settings: config.gateway, node: config.node, payoutAddress: config.payoutAddress)
        var local = StratumConfig()
        local.url = gateway.stratumURL
        local.user = config.payoutAddress
        stratum = StratumSource(config: local)
        gateway.log = { [weak self] in self?.miner?.log($0) }
        stratum.shareContext = { [weak self] in self?.shareContext }
    }

    /// While a chosen pool isn't connected the gateway mines solo: its shares
    /// don't count toward pool payouts, but a block pays you in full.
    private var shareContext: String? {
        guard let pool = gateway.pool else { return nil }
        if case .connected = gateway.poolState { return nil }
        return "solo work while \(pool.name) is reconnecting; not sent to the pool, a block would pay you in full"
    }

    var serverDescription: String {
        "Your DATUM Gateway" + (gateway.pool.map { " · pooled with \($0.name)" } ?? " · solo")
    }

    func start() throws {
        if config.payoutAddress.trimmingCharacters(in: .whitespaces).isEmpty {
            throw MinerError.config("Set a payout address first.")
        }
        let info = try rpc.call("getblockchaininfo") as? [String: Any]
        chain = info?["chain"] as? String ?? "?"
        if let pool = gateway.pool {
            // Never send test-chain work to a real pool.
            guard chain == "main" else {
                throw MinerError.config("\(pool.name) is a mainnet pool, but your node is on \(chain). Choose \"None: solo\" or connect a mainnet node.")
            }
        }
        try stratum.start()
    }

    func tick() throws {
        if !gateway.isRunning { try startGateway() }
        if gateway.poolConnectionLooping && restartForFreshSession() { return }
        miner?.updateStatus { $0.gatewayStatus = self.statusText }
        recordFoundBlocks()
        guard Date() >= readyAt else { return }
        try stratum.tick()
        reportNodeProblem()
    }

    /// Starts the gateway, or restarts it after it exited.
    private func startGateway() throws {
        if let last = lastStart {
            Engine.clearWork()
            let output = gateway.recentOutput
            if Date().timeIntervalSince(last) < Self.minimumUptime {
                lastStart = nil  // restart on the next attempt
                throw MinerError.config("The DATUM Gateway exited right after starting: \(output)")
            }
            miner?.log("DATUM Gateway stopped unexpectedly (\(output)); restarting")
        }
        try gateway.start()
        lastStart = Date()
        readyAt = Date().addingTimeInterval(Self.warmup)
    }

    /// The pool keeps dropping the connection: restart the gateway for a fresh
    /// session, at most once per interval; otherwise just say so. Returns true
    /// when it restarted.
    private func restartForFreshSession() -> Bool {
        let poolName = gateway.pool?.name ?? "The pool"
        guard Date().timeIntervalSince(lastFreshSession) >= Self.freshSessionInterval else {
            miner?.setWaiting("\(poolName) keeps dropping the connection. Your node still builds the blocks; try another DATUM pool in Mining settings if this continues.")
            return false
        }
        lastFreshSession = Date()
        miner?.log("\(poolName) keeps dropping the connection; restarting your DATUM Gateway for a fresh session")
        lastStart = nil  // a deliberate restart, not a crash
        gateway.stop()
        return true  // the next tick starts it again
    }

    /// The gateway keeps serving its last job while it can't reach the node, so
    /// show that as waiting instead of normal mining.
    private func reportNodeProblem() {
        if let problem = gateway.nodeProblem {
            miner?.setWaiting(problem)
            showingNodeProblem = true
        } else if showingNodeProblem {
            showingNodeProblem = false
            miner?.setMining()
        }
    }

    private var showingNodeProblem = false
    private var lastFreshSession = Date.distantPast
    /// At most one deliberate gateway restart per interval, so a pool that's down can't cause a restart loop.
    private static let freshSessionInterval: TimeInterval = 300

    /// The gateway submits the blocks it solves; ask the node whether each one
    /// made it into the chain, and record it like any found block.
    private func recordFoundBlocks() {
        for hash in gateway.takeFoundBlocks() where !seenBlocks.contains(hash) {
            seenBlocks.insert(hash)
            miner?.log("BLOCK SOLVED through your DATUM Gateway: \(hash). Checking with your node...")
            pendingBlocks.append((hash, Date()))
        }
        checkPendingBlocks(final: false)
    }

    /// Looks up solved blocks in the node. `final` (when stopping) checks every
    /// pending block now, so none is lost.
    private func checkPendingBlocks(final: Bool) {
        let now = Date()
        pendingBlocks.removeAll { block in
            guard final || now.timeIntervalSince(block.at) >= Self.blockCheckDelay else { return false }
            let header = try? rpc.call("getblockheader", [block.hash]) as? [String: Any]
            let confirmations = (header?["confirmations"] as? NSNumber)?.intValue ?? -1
            let inChain = confirmations >= 1
            if header == nil && !final && now.timeIntervalSince(block.at) < Self.blockCheckGiveUp { return false }  // node busy or down: retry
            let saved = DatumGatewayProcess.submittedBlocksDirectory.path
            let result: String
            if inChain {
                result = FoundBlock.accepted
            } else if header == nil {
                result = "could not be checked: your node was unreachable. The submitted block is saved in \(saved)"
            } else {
                result = "not in your node's chain (stale or rejected). The submitted block is saved in \(saved)"
            }
            let height = (header?["height"] as? NSNumber)?.intValue ?? status.height ?? 0
            miner?.log("Block \(block.hash) \(result)")
            miner?.recordBlock(FoundBlock(time: block.at, height: height, hash: block.hash, result: result, blockHex: nil, chain: chain))
            return true
        }
    }

    private var status: MinerStatus { miner?.currentStatus ?? MinerStatus() }

    /// Give the node a moment to accept the block before asking; keep asking for
    /// a while if the node is unreachable.
    private static let blockCheckDelay: TimeInterval = 5
    private static let blockCheckGiveUp: TimeInterval = 600

    private var statusText: String {
        switch gateway.poolState {
        case .none: return "Solo through your gateway · your node builds the blocks"
        case .connecting: return "Connecting to \(gateway.pool?.name ?? "pool")… · your node builds the blocks"
        case .connected(let name): return "Pooled with \(name) · your node builds the blocks"
        case .problem(let message): return "Pool problem: \(message)"
        }
    }

    func submit(jobID: UInt64, nonce8: Data) { stratum.submit(jobID: jobID, nonce8: nonce8) }

    func stop() {
        stratum.stop()
        gateway.stop()
        for hash in gateway.takeFoundBlocks() where !seenBlocks.contains(hash) {
            seenBlocks.insert(hash)
            pendingBlocks.append((hash, Date()))
        }
        checkPendingBlocks(final: true)
    }
}
