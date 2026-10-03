import Foundation

/// Human-readable checks of the node setup.
public enum NodeCheck {
    /// blockmaxweight from the node's bitcoin.conf or its GUI settings.json, if set.
    public static func blockMaxWeight(_ node: NodeConfig) -> Int? {
        let dir = URL(fileURLWithPath: node.resolvedDataDir)
        if let data = try? Data(contentsOf: dir.appendingPathComponent("settings.json")),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let v = json["blockmaxweight"] {
            if let n = v as? Int { return n }
            if let s = v as? String, let n = Int(s) { return n }
        }
        guard let conf = try? String(contentsOf: dir.appendingPathComponent("bitcoin.conf"), encoding: .utf8) else { return nil }
        var value: Int?
        for line in conf.split(separator: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("[") { break }  // network-specific sections follow; main section only
            let parts = t.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2, parts[0] == "blockmaxweight" else { continue }
            let number = parts[1].split(separator: "#", omittingEmptySubsequences: false).first ?? ""  // drop a trailing comment
            if let n = Int(number.trimmingCharacters(in: .whitespaces)) { value = n }
        }
        return value
    }

    public static func run(_ config: MinerConfig) -> [String] {
        let rpc = NodeRPC(config.node, timeout: 10)
        var out = [String]()
        do {
            let info = try rpc.call("getblockchaininfo") as? [String: Any] ?? [:]
            let chain = info["chain"] as? String ?? "?"
            let blocks = info["blocks"] as? Int ?? 0
            out.append("✅ Connected: chain \"\(chain)\", height \(blocks.formatted())")
            if !config.node.isLocal {
                out.append("⚠️ The node is on another computer: RPC is unencrypted HTTP, so use it only on a network you trust, or through an SSH tunnel")
            }
            if info["initialblockdownload"] as? Bool == true { out.append("⚠️ The node is still syncing; wait until it finishes.") }
            let networkInfo = try? rpc.call("getnetworkinfo") as? [String: Any]
            if let sub = networkInfo?["subversion"] as? String { out.append("ℹ️ Node software: \(sub)") }
            do {
                let t = try rpc.call("getblocktemplate", [["rules": ["segwit", "blake2b"]]]) as? [String: Any] ?? [:]
                let v = (t["version"] as? NSNumber)?.uint32Value ?? 0
                out.append(v & HeaderV2.versionFlag != 0
                           ? "✅ Templates are BLAKE2b (header v2) blocks"
                           : "❌ Templates are not BLAKE2b blocks. Is this the BLAKE2b chain?")
            } catch {
                out.append("❌ getblocktemplate failed: \(error.localizedDescription)")
            }
            if config.mode == .datum && !config.gateway.poolID.isEmpty {
                switch NodeCheck.blockMaxWeight(config.node) {
                case let w? where w <= 785_000:
                    out.append("✅ blockmaxweight=\(w) leaves room for DATUM pool payouts")
                case let w?:
                    out.append("⚠️ blockmaxweight=\(w) is too high for DATUM pooling; set blockmaxweight=785000 in bitcoin.conf and restart Knots")
                case nil:
                    out.append("⚠️ For DATUM pooling add blockmaxweight=785000 to bitcoin.conf (in \(config.node.resolvedDataDir)) and restart Knots, so blocks have room for the pool's payouts")
                }
            }
            let address = config.payoutAddress.trimmingCharacters(in: .whitespaces)
            if address.isEmpty {
                out.append("⚠️ No payout address set")
            } else {
                let v = try rpc.call("validateaddress", [address]) as? [String: Any] ?? [:]
                guard v["isvalid"] as? Bool == true else {
                    out.append("❌ \(address) is not a valid address on this chain")
                    return out
                }
                out.append("✅ Payout address is valid")
                let wallets = (try? rpc.call("listwallets") as? [String]) ?? []
                let owner = wallets.first { w in
                    ((try? rpc.call("getaddressinfo", [address], wallet: w) as? [String: Any])?["ismine"] as? Bool) == true
                }
                if let owner = owner {
                    out.append("✅ Address belongs to your wallet \"\(owner.isEmpty ? "(default)" : owner)\"")
                } else if wallets.isEmpty {
                    out.append("ℹ️ No wallet loaded in the node, so ownership of the address can't be checked")
                } else {
                    out.append("⚠️ The address is not in any wallet loaded in this node. Make sure you control it!")
                }
            }
        } catch {
            out.append("❌ \(error.localizedDescription)")
        }
        return out
    }
}
