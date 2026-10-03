import Foundation

/// Checks a Stratum server without mining: connect, subscribe, authorize, and
/// parse a real job. Used by "Test Server" in the app and `b2bminer probe`.
public enum StratumProbe {
    public struct Report {
        public var lines: [String] = []
        public var compatible = false
    }

    public static func run(_ config: StratumConfig, timeout: TimeInterval = 20) -> Report {
        var report = Report()
        let endpoint: StratumConfig.Endpoint
        do { endpoint = try config.endpoint() } catch {
            report.lines.append("❌ \(error.localizedDescription)")
            return report
        }
        let c = StratumConnection(endpoint)
        c.start(user: config.user, password: config.password)
        defer { c.close(nil) }

        let deadline = Date().addingTimeInterval(timeout)
        var connected = false, subscribed = false, authorized: Bool?, job: StratumJob?, difficulty: Double?
        var extranonce: (Data, Int)?
        while Date() < deadline {
            switch c.state {
            case .open where !connected:
                connected = true
                report.lines.append("✅ Connected to \(endpoint.host):\(endpoint.port)\(endpoint.tls ? " (TLS)" : "")")
            case .closed(let reason):
                report.lines.append("❌ \(reason ?? "connection closed")")
                return report
            default:
                break
            }
            for m in c.drain() {
                let params = m["params"] as? [Any] ?? []
                switch m["method"] as? String {
                case "mining.set_difficulty":
                    difficulty = (params.first as? NSNumber)?.doubleValue
                case "mining.notify" where job == nil:
                    do { job = try StratumJob(params: params) } catch {
                        report.lines.append("❌ \(error.localizedDescription)")
                        return report
                    }
                case nil:
                    let id = (m["id"] as? NSNumber)?.intValue
                    if id == 1 {
                        extranonce = parseSubscribe(m["result"])
                        subscribed = extranonce != nil
                        report.lines.append(subscribed ? "✅ Subscribed" : "❌ Subscribe failed: \(stratumErrorText(m["error"]) ?? "unexpected reply")")
                        if !subscribed { return report }
                    } else if id == 2 {
                        let ok = m["result"] as? Bool == true
                        authorized = ok
                        report.lines.append(ok ? "✅ Authorized as \(config.user)"
                            : "❌ Not authorized as \(config.user): \(stratumErrorText(m["error"]) ?? "rejected"). Use a valid payout address as the username.")
                    }
                default:
                    break
                }
            }
            if subscribed, authorized != nil, job != nil { break }
            Thread.sleep(forTimeInterval: 0.1)
        }
        guard let j = job, let (en1, en2Size) = extranonce else {
            report.lines.append("❌ No mining job received within \(Int(timeout)) seconds")
            return report
        }
        let input = j.input(extranonce1: en1, extranonce2: Data(count: en2Size))
        report.lines.append("✅ Received a BLAKE2b header-v2 job (80-byte work, extranonce2 \(en2Size) bytes)")
        if let d = difficulty {
            report.lines.append("ℹ️ Share difficulty \(formatDifficulty(d)): about one share per \(formatDuration(d * hashesPerDifficulty / 150e6)) at 150 MH/s")
        }
        report.compatible = authorized == true && input.count == 80
        return report
    }
}
