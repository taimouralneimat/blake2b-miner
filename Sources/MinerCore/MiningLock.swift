import Darwin
import Foundation

/// One miner at a time per data directory. The app and b2bminer hold this lock
/// while mining, so a second copy can't start a second DATUM Gateway on the same
/// port (the two would keep stopping each other's) or split the CPU with the first.
/// The lock is an flock(2) on a file, so it is released even if a miner crashes.
final class MiningLock {
    private let fd: Int32

    static var file: URL { FoundBlocks.directory.appendingPathComponent("mining.lock") }

    private init(fd: Int32) { self.fd = fd }

    deinit {
        flock(fd, LOCK_UN)
        close(fd)
    }

    enum Result {
        case acquired(MiningLock)
        /// Another miner holds the lock; its executable's path if known.
        case heldBy(String?)
        /// The lock file can't be created; mining goes ahead unguarded.
        case unavailable
    }

    static func acquire() -> Result {
        try? FileManager.default.createDirectory(at: FoundBlocks.directory, withIntermediateDirectories: true)
        // O_CLOEXEC: the DATUM Gateway, a child process, must not inherit (and keep holding) the lock.
        let fd = open(file.path, O_RDWR | O_CREAT | O_CLOEXEC, 0o600)
        guard fd >= 0 else { return .unavailable }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            let holder = holderPath(fd)
            close(fd)
            return .heldBy(holder)
        }
        let pid = Data("\(getpid())\n".utf8)
        ftruncate(fd, 0)
        _ = pid.withUnsafeBytes { pwrite(fd, $0.baseAddress, $0.count, 0) }
        return .acquired(MiningLock(fd: fd))
    }

    /// The path of the process whose PID the lock file holds.
    private static func holderPath(_ fd: Int32) -> String? {
        var buffer = [UInt8](repeating: 0, count: 32)
        let n = pread(fd, &buffer, buffer.count, 0)
        guard n > 0, let pid = pid_t(String(decoding: buffer[..<n], as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)), pid > 0 else { return nil }
        var path = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        guard proc_pidpath(pid, &path, UInt32(path.count)) > 0 else { return nil }
        return String(cString: path)
    }

    /// "the BLAKE2b Miner app in /Applications" or "b2bminer (/path)", for messages.
    static func describe(_ path: String?) -> String {
        guard let path = path else { return "another copy of BLAKE2b Miner" }
        if let r = path.range(of: ".app/") {
            let app = String(path[..<r.lowerBound]) + ".app"
            return "another copy of BLAKE2b Miner (\((app as NSString).abbreviatingWithTildeInPath))"
        }
        return "another miner (\((path as NSString).abbreviatingWithTildeInPath))"
    }
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
