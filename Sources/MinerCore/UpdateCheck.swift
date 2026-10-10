import CryptoKit
import Foundation

/// Finds new releases of BLAKE2b Miner on GitHub and downloads them.
public enum UpdateCheck {
    public static let repository = "taimouralneimat/blake2b-miner"

    /// A published release.
    public struct Release: Equatable {
        public let version: String
        public let notes: String
        public let page: URL
        /// The macOS .zip and the release's SHA256SUMS.txt.
        public let zip: URL?
        public let checksums: URL?

        public init(version: String, notes: String, page: URL, zip: URL?, checksums: URL?) {
            self.version = version
            self.notes = notes
            self.page = page
            self.zip = zip
            self.checksums = checksums
        }
    }

    /// The latest release, from GitHub's API.
    public static func latest() async throws -> Release {
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue(Miner.userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String,
              let page = (json["html_url"] as? String).flatMap(URL.init(string:)) else {
            throw MinerError.config("GitHub didn't return the latest release")
        }
        let assets = (json["assets"] as? [[String: Any]]) ?? []
        func asset(_ matches: (String) -> Bool) -> URL? {
            assets.first { matches($0["name"] as? String ?? "") }
                .flatMap { ($0["browser_download_url"] as? String).flatMap(URL.init(string:)) }
                .flatMap { isTrusted($0) ? $0 : nil }
        }
        return Release(version: tag.hasPrefix("v") ? String(tag.dropFirst()) : tag,
                       notes: json["body"] as? String ?? "",
                       page: page,
                       zip: asset { $0.hasSuffix("-macOS.zip") },
                       checksums: asset { $0 == "SHA256SUMS.txt" })
    }

    /// Downloads only come from this repository's releases on GitHub.
    static func isTrusted(_ url: URL) -> Bool {
        url.scheme == "https" && url.host == "github.com" && url.path.hasPrefix("/\(repository)/releases/download/")
    }

    /// True if `version` is newer than `current` ("1.10.0" > "1.9.2").
    public static func isNewer(_ version: String, than current: String) -> Bool {
        let a = numbers(version), b = numbers(current)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    private static func numbers(_ version: String) -> [Int] {
        version.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
    }

    /// Downloads the release's .zip into a temporary folder and checks its SHA-256
    /// against the release's SHA256SUMS.txt. Returns the .zip's location.
    public static func download(_ release: Release) async throws -> URL {
        guard let zipURL = release.zip, let sumsURL = release.checksums else {
            throw MinerError.config("The release has no macOS download")
        }
        let (sums, _) = try await URLSession.shared.data(from: sumsURL)
        let name = zipURL.lastPathComponent
        let expected = String(decoding: sums, as: UTF8.self).split(separator: "\n")
            .first { $0.hasSuffix(" " + name) || $0.hasSuffix("*" + name) }
            .map { String($0.prefix { !$0.isWhitespace }).lowercased() }
        guard let expected = expected, expected.count == 64 else {
            throw MinerError.config("SHA256SUMS.txt doesn't list \(name)")
        }
        let (temp, _) = try await URLSession.shared.download(from: zipURL)
        let data = try Data(contentsOf: temp, options: .mappedIfSafe)
        let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard actual == expected else {
            throw MinerError.config("The download's checksum doesn't match SHA256SUMS.txt")
        }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("BLAKE2bMiner-update-\(release.version)")
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let zip = folder.appendingPathComponent(name)
        try FileManager.default.moveItem(at: temp, to: zip)
        return zip
    }
}
