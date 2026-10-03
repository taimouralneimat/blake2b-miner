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

    /// The most transaction weight a node should put in a block when mining through
    /// a DATUM pool, leaving room in the coinbase for the pool's payout outputs.
    public static let datumBlockMaxWeight = 785_000

    /// Runs every check; each line starts with ✅, ⚠️, ❌ or ℹ️.
    public static func run(_ config: MinerConfig) -> [String] {
        let rpc = NodeRPC(config.node, timeout: 10)
        var out = [String]()
        do {
            out += try connection(rpc, config.node)
            out += templates(rpc)
            if config.mode == .datum && !config.gateway.poolID.isEmpty { out += blockWeight(config.node) }
            out += try payoutAddress(rpc, config.payoutAddress)
        } catch {
            out.append("❌ \(error.localizedDescription)")
        }
        return out
    }

    private static func connection(_ rpc: NodeRPC, _ node: NodeConfig) throws -> [String] {
        let info = try rpc.call("getblockchaininfo") as? [String: Any] ?? [:]
        var out = ["✅ Connected: chain \"\(info["chain"] as? String ?? "?")\", height \((info["blocks"] as? Int ?? 0).formatted())"]
        if !node.isLocal {
            out.append("⚠️ The node is on another computer: RPC is unencrypted HTTP, so use it only on a network you trust, or through an SSH tunnel")
        }
        if info["initialblockdownload"] as? Bool == true { out.append("⚠️ The node is still syncing; wait until it finishes.") }
        if let version = (try? rpc.call("getnetworkinfo") as? [String: Any])?["subversion"] as? String {
            out.append("ℹ️ Node software: \(version)")
        }
        return out
    }

    private static func templates(_ rpc: NodeRPC) -> [String] {
        do {
            let t = try rpc.call("getblocktemplate", [["rules": SoloSource.rules]]) as? [String: Any] ?? [:]
            let version = (t["version"] as? NSNumber)?.uint32Value ?? 0
            return [version & HeaderV2.versionFlag != 0
                    ? "✅ Templates are BLAKE2b (header v2) blocks"
                    : "❌ Templates are not BLAKE2b blocks. Is this the BLAKE2b chain?"]
        } catch {
            return ["❌ getblocktemplate failed: \(error.localizedDescription)"]
        }
    }

    private static func blockWeight(_ node: NodeConfig) -> [String] {
        let limit = datumBlockMaxWeight
        switch blockMaxWeight(node) {
        case let w? where w <= limit:
            return ["✅ blockmaxweight=\(w) leaves room for DATUM pool payouts"]
        case let w?:
            return ["⚠️ blockmaxweight=\(w) is too high for DATUM pooling; set blockmaxweight=\(limit) in bitcoin.conf and restart Knots"]
        case nil:
            return ["⚠️ For DATUM pooling add blockmaxweight=\(limit) to bitcoin.conf (in \(node.resolvedDataDir)) and restart Knots, so blocks have room for the pool's payouts"]
        }
    }

    private static func payoutAddress(_ rpc: NodeRPC, _ raw: String) throws -> [String] {
        let address = raw.trimmingCharacters(in: .whitespaces)
        guard !address.isEmpty else { return ["⚠️ No payout address set"] }
        let v = try rpc.call("validateaddress", [address]) as? [String: Any] ?? [:]
        guard v["isvalid"] as? Bool == true else { return ["❌ \(address) is not a valid address on this chain"] }
        let wallets = (try? rpc.call("listwallets") as? [String]) ?? []
        let owner = wallets.first { w in
            ((try? rpc.call("getaddressinfo", [address], wallet: w) as? [String: Any])?["ismine"] as? Bool) == true
        }
        if let owner = owner {
            return ["✅ Payout address is valid", "✅ Address belongs to your wallet \"\(owner.isEmpty ? "(default)" : owner)\""]
        }
        return ["✅ Payout address is valid", wallets.isEmpty
                ? "ℹ️ No wallet loaded in the node, so ownership of the address can't be checked"
                : "⚠️ The address is not in any wallet loaded in this node. Make sure you control it!"]
    }
}
