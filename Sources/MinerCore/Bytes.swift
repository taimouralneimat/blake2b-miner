import CEngine
import CryptoKit
import Foundation

public enum HexError: Error { case invalid(String) }

extension Data {
    /// Parses a hex string (no prefix). Throws on odd length or bad digits.
    public init(hex: String) throws {
        let chars = Array(hex.utf8)
        guard chars.count % 2 == 0 else { throw HexError.invalid(hex) }
        var bytes = [UInt8]()
        bytes.reserveCapacity(chars.count / 2)
        func nibble(_ c: UInt8) throws -> UInt8 {
            switch c {
            case 48...57: return c - 48
            case 97...102: return c - 87
            case 65...70: return c - 55
            default: throw HexError.invalid(hex)
            }
        }
        var i = 0
        while i < chars.count {
            bytes.append(try nibble(chars[i]) << 4 | nibble(chars[i + 1]))
            i += 2
        }
        self.init(bytes)
    }

    public var hex: String { map { String(format: "%02x", $0) }.joined() }

    /// Display order of a uint256 (RPC hex) is the internal bytes reversed.
    public var reversedData: Data { Data(reversed()) }

    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        var v = value.littleEndian
        Swift.withUnsafeBytes(of: &v) { append(contentsOf: $0) }
    }

    func readLE<T: FixedWidthInteger>(_: T.Type, at offset: Int) -> T {
        var v: T = 0
        for i in 0..<MemoryLayout<T>.size {
            v |= T(self[startIndex + offset + i]) << (8 * i)
        }
        return v
    }
}

enum Hash {
    static func sha256(_ data: Data) -> Data { Data(SHA256.hash(data: data)) }

    static func sha256d(_ data: Data) -> Data { sha256(sha256(data)) }

    /// BIP340-style tagged hash: SHA256(SHA256(tag) || SHA256(tag) || data).
    static func tagged(_ tag: String, _ data: Data) -> Data {
        let t = sha256(Data(tag.utf8))
        return sha256(t + t + data)
    }

    static func blake2b256(_ data: Data) -> Data {
        var out = [UInt8](repeating: 0, count: 32)
        data.withUnsafeBytes { b2m_blake2b256(&out, $0.bindMemory(to: UInt8.self).baseAddress, data.count) }
        return Data(out)
    }
}

/// 256-bit unsigned integer, just enough for proof-of-work targets.
public struct UInt256: Comparable, CustomStringConvertible {
    /// Exactly four words, most significant first.
    public private(set) var words: [UInt64]

    public init(words: [UInt64]) {
        precondition(words.count == 4, "UInt256 needs exactly 4 words")
        self.words = words
    }

    /// From 32 bytes in little-endian order (Bitcoin's internal uint256 layout).
    public init(littleEndian data: Data) {
        let be = Array(data.reversed())
        self.init(bigEndian: Data(be))
    }

    /// From 32 bytes in big-endian order.
    public init(bigEndian data: Data) {
        precondition(data.count == 32)
        var w = [UInt64]()
        for i in 0..<4 {
            var v: UInt64 = 0
            for b in 0..<8 { v = v << 8 | UInt64(data[data.startIndex + 8 * i + b]) }
            w.append(v)
        }
        words = w
    }

    /// Decodes a compact "nBits" target. Returns nil for negative or overflowing values.
    public init?(compact bits: UInt32) {
        let exponent = Int(bits >> 24)
        let mantissa = UInt64(bits & 0x007f_ffff)
        if bits & 0x0080_0000 != 0 && mantissa != 0 { return nil }
        var bytes = [UInt8](repeating: 0, count: 32)  // big-endian
        let m = [UInt8((mantissa >> 16) & 0xff), UInt8((mantissa >> 8) & 0xff), UInt8(mantissa & 0xff)]
        for (i, byte) in m.enumerated() {
            let pos = 32 - exponent + i  // index from the most significant end
            if pos < 0 {
                if byte != 0 { return nil }
                continue
            }
            if pos < 32 { bytes[pos] = byte }
        }
        self.init(bigEndian: Data(bytes))
    }

    public var bigEndianData: Data {
        var d = Data()
        for w in words { d.appendLE(w.byteSwapped) }
        return d
    }

    public var isZero: Bool { words.allSatisfy { $0 == 0 } }

    public static func < (a: UInt256, b: UInt256) -> Bool {
        for i in 0..<4 where a.words[i] != b.words[i] { return a.words[i] < b.words[i] }
        return false
    }

    /// Approximate value as a Double (for difficulty and expected-time math).
    public var doubleValue: Double {
        words.reduce(0.0) { $0 * 18446744073709551616.0 + Double($1) }
    }

    public var description: String { bigEndianData.hex }
}
