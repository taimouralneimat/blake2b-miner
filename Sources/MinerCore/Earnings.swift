import Foundation

/// Mining payouts to your address, read from your own node's wallet. Pool payouts
/// and solo blocks are coinbase outputs, which the wallet lists as "immature"
/// (still maturing), "generate" (spendable) or "orphan" (the block left the chain).
/// This works with any pool, and needs no pool's word for it.
public enum Earnings {
    public struct Payout: Equatable, Identifiable {
        public enum Status: String { case maturing, spendable, orphaned }
        public let txid: String
        public let time: Date
        public let amount: Double
        public let confirmations: Int
        /// Confirmations at which it becomes spendable.
        public let confirmationsNeeded: Int
        public let status: Status

        /// When it becomes spendable, at about 10 minutes a block.
        public var spendableAround: Date? {
            status == .maturing ? Date().addingTimeInterval(Double(max(0, confirmationsNeeded - confirmations)) * 600) : nil
        }
        public var id: String { txid }

        public init(txid: String, time: Date, amount: Double, confirmations: Int, confirmationsNeeded: Int = 6_481,
                    status: Status) {
            self.txid = txid
            self.time = time
            self.amount = amount
            self.confirmations = confirmations
            self.confirmationsNeeded = confirmationsNeeded
            self.status = status
        }
    }

    public struct Summary: Equatable {
        /// The wallet holding the address.
        public let wallet: String
        public let payouts: [Payout]
        public var spendable: Double { total(.spendable) }
        public var maturing: Double { total(.maturing) }

        public init(wallet: String, payouts: [Payout]) {
            self.wallet = wallet
            self.payouts = payouts
        }

        private func total(_ status: Payout.Status) -> Double {
            payouts.filter { $0.status == status }.reduce(0) { $0 + $1.amount }
        }
    }

    /// Confirmations before mined coins can be spent through your node. Knots 29.4.2
    /// accepts no spend of a coinbase younger than 6,480 blocks into its mempool
    /// (about 45 days), whatever height it was mined at; as consensus, the rule
    /// covers blocks 973,440 to 979,919. The wallet counts 100, so it isn't asked.
    public static let confirmationsToSpend = 6_481

    /// How many recent wallet transactions are searched for payouts.
    private static let searched = 1000

    /// The payouts to `address`, newest first; nil if no wallet loaded in the node has
    /// the address.
    public static func summary(node: NodeConfig, address: String) throws -> Summary? {
        let rpc = NodeRPC(node, timeout: 20)
        let wallets = (try rpc.call("listwallets") as? [String]) ?? []
        guard let wallet = wallets.first(where: { w in
            let info = (try? rpc.call("getaddressinfo", [address], wallet: w)) as? [String: Any]
            return info?["ismine"] as? Bool == true || info?["iswatchonly"] as? Bool == true
        }) else { return nil }
        let transactions = (try rpc.call("listtransactions", ["*", searched, 0, true], wallet: wallet) as? [[String: Any]]) ?? []
        let payouts = transactions.compactMap { t -> Payout? in
            guard t["address"] as? String == address, let txid = t["txid"] as? String else { return nil }
            let confirmations = t["confirmations"] as? Int ?? 0
            let needed = confirmationsToSpend
            var status: Payout.Status
            switch t["category"] as? String {
            case "immature": status = .maturing
            case "generate": status = .spendable
            case "orphan": status = .orphaned
            default: return nil
            }
            // Don't count on the wallet knowing the 45-day rule.
            if status == .spendable && confirmations < needed { status = .maturing }
            return Payout(txid: txid,
                          time: Date(timeIntervalSince1970: t["time"] as? Double ?? 0),
                          amount: t["amount"] as? Double ?? 0,
                          confirmations: confirmations,
                          confirmationsNeeded: needed,
                          status: status)
        }
        return Summary(wallet: wallet, payouts: payouts.sorted { $0.time > $1.time })
    }
}
