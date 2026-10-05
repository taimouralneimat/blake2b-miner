import Foundation

/// Every solved block, accepted or not, with its full hex so it can be resubmitted by hand.
/// Stored as JSON lines in ~/Library/Application Support/BLAKE2bMiner/found-blocks.jsonl
public enum FoundBlocks {
    /// ~/Library/Application Support/BLAKE2bMiner (B2B_DATA_DIR overrides it, for tests).
    public static var directory: URL {
        if let dir = ProcessInfo.processInfo.environment["B2B_DATA_DIR"] { return URL(fileURLWithPath: dir, isDirectory: true) }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("BLAKE2bMiner", isDirectory: true)
    }

    public static var file: URL { directory.appendingPathComponent("found-blocks.jsonl") }

    public static func append(_ block: FoundBlock) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var line = try encoder.encode(block)
        line.append(0x0a)
        try appendData(line, to: file)
    }

    /// Appends to a file, creating it if needed. Unlike FileHandle's older
    /// write(_:), a failed write (say, a full disk) throws instead of crashing.
    public static func appendData(_ data: Data, to url: URL) throws {
        guard let handle = try? FileHandle(forWritingTo: url) else {
            try data.write(to: url)
            return
        }
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
    }

    public static func all() -> [FoundBlock] {
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return text.split(separator: "\n").compactMap { try? decoder.decode(FoundBlock.self, from: Data($0.utf8)) }
    }
}
