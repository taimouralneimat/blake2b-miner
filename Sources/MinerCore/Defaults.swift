import Foundation

extension KeyedDecodingContainer {
    /// Decodes `key`, or returns `fallback` when it is missing or invalid, so
    /// settings saved by an older or newer version never reset everything.
    public func decode<T: Decodable>(_ key: Key, or fallback: T) -> T {
        (try? decodeIfPresent(T.self, forKey: key)) ?? fallback
    }
}
