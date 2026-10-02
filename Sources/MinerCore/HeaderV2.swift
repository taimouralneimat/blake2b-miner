import Foundation

/// A Bitcoin Knots header-v2 (BLAKE2b proof of work) block header.
///
/// Mirrors `CBlockHeader` and `CBlockHeader::GetHash()` in
/// `src/primitives/block.cpp` of Bitcoin Knots v29.4.1.knots20260508.
/// Hashes (`prev`, `merkle`, `mmRHS`) and the 128-bit fields are kept in
/// internal byte order, as serialized.
public struct HeaderV2: Equatable {
    public static let versionFlag: UInt32 = 0x8000_0000
    public static let useTimeOffset: UInt8 = 4
    public static let serializedSize = 164

    public var version: UInt32  // without the v2 flag
    public var prev: Data
    public var merkle: Data
    public var time: UInt32
    public var bits: UInt32
    public var nonce: UInt32 = 0
    public var nonce2: UInt32 = 0
    public var nonce3: UInt32 = 0
    public var extranonce = Data(count: 16)
    public var timeOffset: UInt32 = 0
    public var txCount: UInt16 = 0
    public var flags: UInt8 = 0
    public var xorClearBits: UInt8 = 0
    public var xorKey = Data(count: 16)
    public var height: Int32 = 0
    public var mmRHS = Data(count: 32)

    public init(version: UInt32, prev: Data, merkle: Data, time: UInt32, bits: UInt32) {
        self.version = version & ~Self.versionFlag
        self.prev = prev
        self.merkle = merkle
        self.time = time
        self.bits = bits
    }

    public var completeVersion: UInt32 { Self.versionFlag | version }

    public var timeOnWire: UInt32 {
        flags & Self.useTimeOffset != 0 ? time &- timeOffset : time
    }

    public func serialize() -> Data {
        var d = Data()
        d.appendLE(completeVersion)
        d += prev
        d += merkle
        d.appendLE(timeOnWire)
        d.appendLE(bits)
        d.appendLE(nonce)
        d.appendLE(nonce2)
        d.appendLE(nonce3)
        d += extranonce
        d.appendLE(timeOffset)
        d.appendLE(txCount)
        d.append(flags)
        d.append(xorClearBits)
        d += xorKey
        d.appendLE(height)
        d += mmRHS
        return d
    }

    public init(serialized d: Data) throws {
        let d = Data(d)  // rebase indices to 0
        guard d.count == Self.serializedSize, d.readLE(UInt32.self, at: 0) & Self.versionFlag != 0 else {
            throw MinerError.protocolError("not a header-v2 block header")
        }
        self.init(version: d.readLE(UInt32.self, at: 0), prev: d[4..<36], merkle: d[36..<68],
                  time: 0, bits: d.readLE(UInt32.self, at: 72))
        prev = Data(prev)
        merkle = Data(merkle)
        nonce = d.readLE(UInt32.self, at: 76)
        nonce2 = d.readLE(UInt32.self, at: 80)
        nonce3 = d.readLE(UInt32.self, at: 84)
        extranonce = Data(d[88..<104])
        timeOffset = d.readLE(UInt32.self, at: 104)
        txCount = d.readLE(UInt16.self, at: 108)
        flags = d[110]
        xorClearBits = d[111]
        xorKey = Data(d[112..<128])
        height = d.readLE(Int32.self, at: 128)
        mmRHS = Data(d[132..<164])
        let wire = d.readLE(UInt32.self, at: 68)
        time = flags & Self.useTimeOffset != 0 ? wire &+ timeOffset : wire
    }

    // MARK: Proof of work

    var xorMask: Data {
        guard xorKey.contains(where: { $0 != 0 }) else { return Data(count: 32) }
        var mask = Hash.tagged("Bitcoin block hash PoW XOR mask", xorKey)
        let clearBytes = Int(xorClearBits) / 8
        for i in 0..<min(clearBytes, 32) { mask[i] = 0 }
        if clearBytes < 32 { mask[clearBytes] &= 0xff >> (xorClearBits % 8) }
        return mask
    }

    /// The hidden previous-block value seen by hashers (first 6 bytes zeroed).
    public var prevBlockHidden: Data {
        var h = Hash.tagged("Bitcoin prevblock header, hashed", prev.reversedData)
        for i in 0..<6 { h[i] = 0 }
        return h
    }

    /// The merge-mining hook commitment ("h2"); fixed for a given template.
    public var h2: Data {
        let xorKeyHash = Hash.tagged("Bitcoin block hash PoW XOR key", xorKey)
        var h1 = Data()
        h1.appendLE(completeVersion)
        h1 += prev.reversedData
        h1.appendLE(height)
        h1 += merkle
        h1.appendLE(timeOnWire)
        h1.append(0)  // reserved for extended 40-bit time
        h1.appendLE(bits)
        h1.appendLE(UInt32(txCount))
        h1.append(flags)
        h1.append(xorClearBits)
        h1 += xorKeyHash
        return Hash.tagged("Merge-mining hook", Hash.tagged("Bitcoin block header 1", h1) + Data(count: 32) + mmRHS)
    }

    /// First BLAKE2b stage ("work root" in Stratum terms).
    public func blake2b1(h2: Data? = nil) -> Data {
        Hash.blake2b256(Data(count: 4) + (h2 ?? self.h2) + extranonce)
    }

    /// Input to the final BLAKE2b stage; layout depends on `flags & 3`.
    public func asicInput() -> Data {
        let h2 = self.h2
        let b1 = blake2b1(h2: h2)
        var d = Data()
        switch flags & 3 {
        case 0:
            var hidden = Hash.tagged("Bitcoin prevblock header, hashed", prev.reversedData)
            for i in 0..<6 { hidden[i] = 0 }
            d += hidden
            d.appendLE(nonce); d.appendLE(nonce2); d.appendLE(timeOffset); d.appendLE(nonce3)
            d += b1
        case 1:
            d.appendLE(nonce); d.appendLE(nonce2); d.appendLE(nonce3); d.appendLE(timeOffset)
            d += b1 + h2
        default:
            d += Data(count: 16 * (flags & 3 == 3 ? 5 : 3))
            d += h2
            d.appendLE(nonce); d.appendLE(nonce2); d.appendLE(timeOffset); d.appendLE(nonce3)
            d += b1
        }
        return d
    }

    /// Block hash in internal byte order (reverse for display).
    public var hash: Data {
        let b2 = Hash.blake2b256(asicInput())
        let mask = xorMask
        return Data((0..<32).map { b2[$0] ^ mask[$0] }.reversed())
    }

    public var hashHex: String { hash.reversedData.hex }

    public var target: UInt256? { UInt256(compact: bits) }

    public var meetsTarget: Bool {
        guard let t = target else { return false }
        return UInt256(littleEndian: hash) <= t
    }
}

/// Network difficulty relative to the classic difficulty-1 target.
public func difficulty(bits: UInt32) -> Double {
    guard let t = UInt256(compact: bits), !t.isZero, let one = UInt256(compact: 0x1d00ffff) else { return 0 }
    return one.doubleValue / t.doubleValue
}
