import Foundation

/// Mines through the bundled DATUM Gateway: runs the gateway next to the
/// user's node (which builds the blocks) and takes work from its Stratum port.
final class GatewaySource: WorkSource {
    weak var miner: Miner? {
        didSet { stratum.miner = miner }
    }

    private let config: MinerConfig
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
        gateway = DatumGatewayProcess(settings: config.gateway, node: config.node, payoutAddress: config.payoutAddress)
        var local = StratumConfig()
        local.url = gateway.stratumURL
        local.user = config.payoutAddress
        stratum = StratumSource(config: local)
        gateway.log = { [weak self] in self?.miner?.log($0) }
    }

    var serverDescription: String {
        "Your DATUM Gateway" + (gateway.pool.map { " · pooled with \($0.name)" } ?? " · solo")
    }

    func start() throws {
        if config.payoutAddress.trimmingCharacters(in: .whitespaces).isEmpty {
            throw MinerError.config("Set a payout address first.")
        }
        if let pool = gateway.pool {
            // Never send test-chain work to a real pool.
            let info = try NodeRPC(config.node, timeout: 10).call("getblockchaininfo") as? [String: Any]
            let chain = info?["chain"] as? String ?? "?"
            guard chain == "main" else {
                throw MinerError.config("\(pool.name) is a mainnet pool, but your node is on \(chain). Choose \"None: solo\" or connect a mainnet node.")
            }
        }
        try stratum.start()
    }

    func tick() throws {
        if !gateway.isRunning {
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
        miner?.updateStatus { $0.gatewayStatus = self.statusText }
        guard Date() >= readyAt else { return }
        try stratum.tick()
    }

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
    }
}
