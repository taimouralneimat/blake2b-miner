import Foundation

/// A quick, offline check of a payout address as the user types it.
/// The node does the authoritative check (`validateaddress` in Test Node
/// Connection and before mining); this only catches obvious mistakes early.
public enum AddressFormat {
    public enum Verdict: Equatable {
        case empty
        case looksValid
        case invalid(String)
    }

    private static let base58 = Set("123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz")
    private static let bech32 = Set("qpzry9x8gf2tvdw0s3jn54khce6mua7l")

    public static func check(_ raw: String) -> Verdict {
        let address = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if address.isEmpty { return .empty }
        let lower = address.lowercased()
        if let hrp = ["bc1", "tb1", "bcrt1"].first(where: { lower.hasPrefix($0) }) {
            guard address == lower || address == address.uppercased() else {
                return .invalid("Mixes upper- and lowercase letters")
            }
            let data = lower.dropFirst(hrp.count)
            guard (14 + hrp.count...90).contains(address.count) else { return .invalid("Wrong length for a bech32 address") }
            guard data.allSatisfy(bech32.contains) else { return .invalid("Contains a character that bech32 addresses never use") }
            return .looksValid
        }
        if let first = address.first, "13mn2".contains(first) {
            guard (26...35).contains(address.count) else { return .invalid("Wrong length for a legacy address") }
            guard address.allSatisfy(base58.contains) else { return .invalid("Contains 0, O, I or l, which addresses never use") }
            return .looksValid
        }
        return .invalid("Bitcoin addresses start with bc1, 1 or 3")
    }
}
