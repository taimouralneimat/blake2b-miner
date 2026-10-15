import Foundation

/// An offline check of a payout address as the user types it, checksum included,
/// so a mistyped character is caught before any coins could be sent to it. The node
/// still has the last word (`validateaddress` before mining): it also knows which
/// network it is on.
public enum AddressFormat {
    public enum Verdict: Equatable {
        case empty
        case valid
        case invalid(String)
    }

    public static func check(_ raw: String) -> Verdict {
        let address = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if address.isEmpty { return .empty }
        let lower = address.lowercased()
        if let hrp = ["bc", "tb", "bcrt"].first(where: { lower.hasPrefix($0 + "1") }) {
            guard address == lower || address == address.uppercased() else {
                return .invalid("Mixes upper- and lowercase letters")
            }
            return segwit(lower, hrp: hrp)
        }
        if let first = address.first, "13mn2".contains(first) {
            return base58Check(address)
        }
        return .invalid("Bitcoin addresses start with bc1, 1 or 3")
    }

    // MARK: Segwit (BIP173 bech32, BIP350 bech32m)

    private static let charset = Array("qpzry9x8gf2tvdw0s3jn54khce6mua7l")
    private static let bech32Constant: UInt32 = 1
    private static let bech32mConstant: UInt32 = 0x2bc8_30a3

    private static func segwit(_ address: String, hrp: String) -> Verdict {
        let part = address.dropFirst(hrp.count + 1)
        guard (14 + hrp.count...90).contains(address.count), part.count >= 7 else {
            return .invalid("Wrong length for a bc1 address")
        }
        var values = [UInt8]()
        for c in part {
            guard let v = charset.firstIndex(of: c) else { return .invalid("Contains a character that bc1 addresses never use") }
            values.append(UInt8(v))
        }
        let checksum = polymod(expand(hrp) + values)
        let version = values[0]
        // Version 0 uses bech32, versions 1 to 16 bech32m (BIP350).
        guard checksum == (version == 0 ? bech32Constant : bech32mConstant) else {
            return .invalid("The checksum doesn't match: a character is mistyped")
        }
        guard version <= 16, let program = regroup(values.dropFirst().dropLast(6)),
              (2...40).contains(program.count), version != 0 || [20, 32].contains(program.count) else {
            return .invalid("Not a valid segwit address")
        }
        return .valid
    }

    private static func polymod(_ values: [UInt8]) -> UInt32 {
        let generator: [UInt32] = [0x3b6a_57b2, 0x2650_8e6d, 0x1ea1_19fa, 0x3d42_33dd, 0x2a14_62b3]
        var chk: UInt32 = 1
        for v in values {
            let top = chk >> 25
            chk = (chk & 0x1ff_ffff) << 5 ^ UInt32(v)
            for i in 0..<5 where (top >> i) & 1 == 1 { chk ^= generator[i] }
        }
        return chk
    }

    private static func expand(_ hrp: String) -> [UInt8] {
        let bytes = Array(hrp.utf8)
        return bytes.map { $0 >> 5 } + [0] + bytes.map { $0 & 31 }
    }

    /// 5-bit groups to bytes; nil if the padding isn't zero.
    private static func regroup(_ values: ArraySlice<UInt8>) -> [UInt8]? {
        var acc = 0, bits = 0, out = [UInt8]()
        for v in values {
            acc = acc << 5 | Int(v)
            bits += 5
            if bits >= 8 {
                bits -= 8
                out.append(UInt8((acc >> bits) & 0xff))
            }
        }
        guard bits < 5, (acc << (8 - bits)) & 0xff == 0 else { return nil }
        return out
    }

    // MARK: Legacy (base58check)

    private static let alphabet = Array("123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz")

    private static func base58Check(_ address: String) -> Verdict {
        guard (26...35).contains(address.count) else { return .invalid("Wrong length for a legacy address") }
        var bytes = [UInt8]()  // big-endian
        for c in address {
            guard let digit = alphabet.firstIndex(of: c) else { return .invalid("Contains 0, O, I or l, which addresses never use") }
            var carry = digit
            for i in stride(from: bytes.count - 1, through: 0, by: -1) {
                carry += Int(bytes[i]) * 58
                bytes[i] = UInt8(carry & 0xff)
                carry >>= 8
            }
            while carry > 0 {
                bytes.insert(UInt8(carry & 0xff), at: 0)
                carry >>= 8
            }
        }
        bytes = Array(repeating: 0, count: address.prefix { $0 == "1" }.count) + bytes
        guard bytes.count == 25 else { return .invalid("Not a valid legacy address") }
        let payload = Data(bytes[0..<21])
        guard Hash.sha256d(payload).prefix(4) == Data(bytes[21...]) else {
            return .invalid("The checksum doesn't match: a character is mistyped")
        }
        // P2PKH and P2SH, main network and test networks.
        guard [0x00, 0x05, 0x6f, 0xc4].contains(bytes[0]) else { return .invalid("Not a Bitcoin address") }
        return .valid
    }
}
