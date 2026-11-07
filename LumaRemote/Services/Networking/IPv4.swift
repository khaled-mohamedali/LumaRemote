import Foundation
import Darwin

/// Minimal IPv4 helpers (parsing, subnet math, local interface lookup).
nonisolated struct IPv4: Hashable, Sendable, Comparable, CustomStringConvertible {
    let value: UInt32

    init(_ value: UInt32) { self.value = value }

    /// Accepts dotted-quad only ("192.168.1.54"); trims whitespace.
    init?(_ string: String) {
        let parts = string.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        var v: UInt32 = 0
        for part in parts {
            guard !part.isEmpty, part.count <= 3, part.allSatisfy(\.isASCII), let octet = UInt8(part) else { return nil }
            v = (v << 8) | UInt32(octet)
        }
        value = v
    }

    var description: String {
        "\(value >> 24 & 0xFF).\(value >> 16 & 0xFF).\(value >> 8 & 0xFF).\(value & 0xFF)"
    }

    static func < (lhs: IPv4, rhs: IPv4) -> Bool { lhs.value < rhs.value }

    var isPrivate: Bool {
        let a = value >> 24, b = (value >> 16) & 0xFF
        return a == 10 || (a == 172 && (16...31).contains(b)) || (a == 192 && b == 168)
    }
}

nonisolated struct LocalInterface: Sendable, Equatable {
    let name: String
    let address: IPv4
    let netmask: IPv4

    var broadcast: IPv4 { IPv4(address.value | ~netmask.value) }

    /// Hosts to scan. Large subnets are clamped to the /24 around our own address so
    /// a scan stays fast (254 hosts max).
    var scanHosts: [IPv4] {
        let mask = max(netmask.value, 0xFFFF_FF00)
        let network = address.value & mask
        let broadcast = network | ~mask
        guard broadcast > network + 1 else { return [] }
        return ((network + 1)..<broadcast).map(IPv4.init).filter { $0 != address }
    }

    /// The Wi-Fi interface (en0), falling back to any other "en" interface with IPv4.
    static func current() -> LocalInterface? {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return nil }
        defer { freeifaddrs(head) }

        var fallback: LocalInterface?
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let entry = pointer.pointee
            guard let addr = entry.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET),
                  let mask = entry.ifa_netmask else { continue }
            let flags = Int32(entry.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0 else { continue }
            let name = String(cString: entry.ifa_name)
            guard name.hasPrefix("en") else { continue }
            let ip = addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                UInt32(bigEndian: $0.pointee.sin_addr.s_addr)
            }
            let nm = mask.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                UInt32(bigEndian: $0.pointee.sin_addr.s_addr)
            }
            let iface = LocalInterface(name: name, address: IPv4(ip), netmask: IPv4(nm))
            if name == "en0" { return iface }
            if fallback == nil { fallback = iface }
        }
        return fallback
    }
}
