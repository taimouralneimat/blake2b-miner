import Foundation

/// What to mine, where, and with which hardware. Saved by the app; built from
/// options by `b2bminer`.
public struct MinerConfig: Codable, Equatable {
    public var mode: MiningMode = .datum
    public var node = NodeConfig()
    public var payoutAddress = ""
    public var coinbaseTag = "/BLAKE2b Miner/"
    public var gateway = GatewaySettings()
    public var stratum = StratumConfig()
    /// Mine with CPU threads (`threads` of them).
    public var useCPU = true
    public var threads = CPUInfo.cores
    /// Mine with the GPU, using `gpuLoad` percent (10...100) of its time.
    public var useGPU = false
    public var gpuLoad = 100
    /// Keep the Mac responsive: CPU threads at utility priority, and the GPU in
    /// short bursts so the screen stays smooth.
    public var lowPriority = false
    public var pauseOnBattery = true
    public var preventSleep = false

    public init() {}

    /// CPU threads to run: 0 when CPU mining is off.
    public var cpuThreads: Int { useCPU ? min(max(threads, 1), Engine.maxThreads) : 0 }

    /// "12 CPU threads + GPU at 75%", for messages.
    public var hardwareDescription: String {
        var parts = [String]()
        if useCPU { parts.append("\(cpuThreads) CPU thread\(cpuThreads == 1 ? "" : "s")") }
        if useGPU { parts.append(gpuLoad >= 100 ? "GPU" : "GPU at \(gpuLoad)%") }
        return parts.isEmpty ? "no hardware" : parts.joined(separator: " + ")
    }

    /// "12 CPU + GPU", "12 CPU" or "GPU", for compact displays.
    public var hardwareShort: String {
        [useCPU ? "\(cpuThreads) CPU" : nil, useGPU && GPUInfo.name != nil ? "GPU" : nil]
            .compactMap { $0 }.joined(separator: " + ")
    }

    /// Missing or invalid keys keep their defaults (see `decode(_:or:)`).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = MinerConfig()
        mode = c.decode(.mode, or: d.mode)
        node = c.decode(.node, or: d.node)
        payoutAddress = c.decode(.payoutAddress, or: d.payoutAddress)
        coinbaseTag = c.decode(.coinbaseTag, or: d.coinbaseTag)
        gateway = c.decode(.gateway, or: d.gateway)
        stratum = c.decode(.stratum, or: d.stratum)
        useCPU = c.decode(.useCPU, or: d.useCPU)
        threads = c.decode(.threads, or: d.threads)
        useGPU = c.decode(.useGPU, or: d.useGPU)
        gpuLoad = c.decode(.gpuLoad, or: d.gpuLoad)
        lowPriority = c.decode(.lowPriority, or: d.lowPriority)
        pauseOnBattery = c.decode(.pauseOnBattery, or: d.pauseOnBattery)
        preventSleep = c.decode(.preventSleep, or: d.preventSleep)
    }
}
