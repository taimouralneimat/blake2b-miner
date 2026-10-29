import Foundation

extension KeyedDecodingContainer {
    /// Decodes `key`, or returns `fallback` when it is missing or invalid, so
    /// settings saved by an older or newer version never reset everything.
    public func decode<T: Decodable>(_ key: Key, or fallback: T) -> T {
        (try? decodeIfPresent(T.self, forKey: key)) ?? fallback
    }
}

/// A value that decodes to nil instead of failing the whole array around it.
public struct Lossy<T: Decodable>: Decodable {
    public let value: T?
    public init(from decoder: Decoder) throws { value = try? T(from: decoder) }
}
