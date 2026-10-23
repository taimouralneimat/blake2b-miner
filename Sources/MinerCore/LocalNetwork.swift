import Foundation

/// The Mac's address on the local network, for sharing the gateway with other miners.
public enum LocalNetwork {
    /// The Mac's primary IPv4 address on the local network.
    public static var address: String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }
        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let ifa = ptr.pointee
            guard let addr = ifa.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET),
                  String(cString: ifa.ifa_name).hasPrefix("en") else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                return String(cString: host)
            }
        }
        return nil
    }

    /// Whether `host` is this Mac or a machine on the local network (loopback,
    /// private IPv4 ranges, link-local, or a ".local" Bonjour name).
    public static func isLocal(_ host: String) -> Bool {
        let h = host.lowercased()
        if h == "localhost" || h == "::1" || h.hasSuffix(".local") { return true }
        let p = h.split(separator: ".").compactMap { Int($0) }
        guard p.count == 4, p.allSatisfy({ (0...255).contains($0) }) else { return false }
        return p[0] == 127 || p[0] == 10 || (p[0] == 192 && p[1] == 168) || (p[0] == 172 && (16...31).contains(p[1]))
            || (p[0] == 169 && p[1] == 254)
    }
}
