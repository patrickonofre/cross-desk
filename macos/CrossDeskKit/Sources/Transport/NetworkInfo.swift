import Foundation

/// Local addresses the server shows in the UI so the user can type them on
/// the client machine.
public enum NetworkInfo {
    /// mDNS hostname (e.g. "MacBook-Pro.local") — stable across DHCP renews,
    /// preferred over raw IPs on a LAN.
    public static func localHostname() -> String {
        ProcessInfo.processInfo.hostName
    }

    /// Non-loopback IPv4 addresses, `(interface, ip)`, physical interfaces
    /// (en*) first so Wi-Fi/Ethernet outranks VPN tunnels. Link-local
    /// (169.254.x) excluded.
    public static func localIPv4Addresses() -> [(interface: String, ip: String)] {
        var addrs: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addrs) == 0 else { return [] }
        defer { freeifaddrs(addrs) }

        var result: [(interface: String, ip: String)] = []
        var pointer = addrs
        while let current = pointer {
            defer { pointer = current.pointee.ifa_next }
            let ifa = current.pointee
            guard let sa = ifa.ifa_addr, sa.pointee.sa_family == UInt8(AF_INET) else { continue }
            let flags = Int32(ifa.ifa_flags)
            guard (flags & IFF_LOOPBACK) == 0, (flags & IFF_UP) != 0 else { continue }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(
                sa, socklen_t(sa.pointee.sa_len),
                &host, socklen_t(host.count),
                nil, 0, NI_NUMERICHOST
            ) == 0 else { continue }

            let ip = String(cString: host)
            guard !ip.hasPrefix("169.254.") else { continue }
            result.append((interface: String(cString: ifa.ifa_name), ip: ip))
        }

        return result.sorted { a, b in
            let aPhysical = a.interface.hasPrefix("en")
            let bPhysical = b.interface.hasPrefix("en")
            if aPhysical != bPhysical { return aPhysical }
            return a.interface < b.interface
        }
    }
}
