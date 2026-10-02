import Foundation

/// Every solved block, accepted or not, with its full hex so it can be resubmitted by hand.
/// Stored as JSON lines in ~/Library/Application Support/BLAKE2bMiner/found-blocks.jsonl
public enum FoundBlocks {
    public static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("BLAKE2bMiner", isDirectory: true)
    }

    public static var file: URL { directory.appendingPathComponent("found-blocks.jsonl") }

    public static func append(_ block: FoundBlock) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard var line = try? encoder.encode(block) else { return }
        line.append(0x0a)
        if let handle = try? FileHandle(forWritingTo: file) {
            handle.seekToEndOfFile()
            handle.write(line)
            try? handle.close()
        } else {
            try? line.write(to: file)
        }
    }

    public static func all() -> [FoundBlock] {
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return text.split(separator: "\n").compactMap { try? decoder.decode(FoundBlock.self, from: Data($0.utf8)) }
    }
}
