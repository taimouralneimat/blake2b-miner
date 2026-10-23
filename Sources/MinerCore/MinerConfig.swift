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
    /// short bursts so the screen stays smooth. Always, when true; otherwise
    /// during `responsiveSchedule`, if it's on.
    public var lowPriority = false
    /// Hours to keep the Mac responsive (say, while you work); full power outside them.
    public var responsiveSchedule = ResponsiveSchedule()
    public var pauseOnBattery = true
    /// Keep the Mac awake while mining (on mains power): a sleeping Mac mines only in
    /// short maintenance wake-ups. On for new installs; `b2bminer` keeps it on too.
    public var preventSleep = true

    public init() {}

    /// Whether your own node builds the blocks you mine: in the gateway and solo modes;
    /// through another gateway only when it runs on your network (a gateway elsewhere,
    /// such as a pool's, is that server's node).
    public var youBuildTheBlocks: Bool {
        guard mode == .stratum else { return true }
        return (try? stratum.endpoint()).map { LocalNetwork.isLocal($0.host) } ?? false
    }

    /// Whether to keep the Mac responsive at `date`: always, or during the schedule.
    public func isResponsive(at date: Date = Date()) -> Bool {
        lowPriority || responsiveSchedule.isActive(at: date)
    }

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
        responsiveSchedule = c.decode(.responsiveSchedule, or: d.responsiveSchedule)
        pauseOnBattery = c.decode(.pauseOnBattery, or: d.pauseOnBattery)
        preventSleep = c.decode(.preventSleep, or: d.preventSleep)
    }
}

/// Hours on chosen days when mining keeps the Mac responsive.
public struct ResponsiveSchedule: Codable, Equatable {
    public var enabled = false
    /// Minutes after midnight; `end` before `start` means the hours span midnight.
    public var start = 9 * 60
    public var end = 17 * 60
    /// Days the hours apply, as Calendar weekdays (1 = Sunday … 7 = Saturday).
    /// Hours past midnight belong to the day they started on.
    public var days: Set<Int> = [2, 3, 4, 5, 6]

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ResponsiveSchedule()
        enabled = c.decode(.enabled, or: d.enabled)
        start = min(max(c.decode(.start, or: d.start), 0), 1439)
        end = min(max(c.decode(.end, or: d.end), 0), 1439)
        days = c.decode(.days, or: d.days).filter { (1...7).contains($0) }
    }

    public func isActive(at date: Date, calendar: Calendar = .current) -> Bool {
        guard enabled, start != end else { return false }
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        let overnight = end < start
        guard overnight ? (minute >= start || minute < end) : (minute >= start && minute < end) else { return false }
        let day = overnight && minute < end ? calendar.date(byAdding: .day, value: -1, to: date) ?? date : date
        return days.contains(calendar.component(.weekday, from: day))
    }

    /// Short day names in the order the calendar shows them, with their weekday numbers.
    public static func orderedDays(_ calendar: Calendar = .current) -> [(weekday: Int, name: String)] {
        let names = calendar.shortWeekdaySymbols
        return (0..<7).map { i in
            let weekday = (calendar.firstWeekday - 1 + i) % 7 + 1
            return (weekday, names[weekday - 1])
        }
    }

    /// "9:00–17:00, Mon–Fri", "9:00–17:00, Mon, Wed, Sat" or "9:00–17:00, every day"
    public var summary: String {
        func time(_ m: Int) -> String { String(format: "%d:%02d", m / 60, m % 60) }
        let hours = "\(time(start))–\(time(end))"
        let names = Calendar(identifier: .gregorian).shortWeekdaySymbols
        switch days {
        case Set(1...7): return hours + ", every day"
        case [2, 3, 4, 5, 6]: return hours + ", \(names[1])–\(names[5])"
        case []: return hours + ", no days chosen"
        default: return hours + ", " + days.sorted { ($0 + 5) % 7 < ($1 + 5) % 7 }.map { names[$0 - 1] }.joined(separator: ", ")
        }
    }
}
