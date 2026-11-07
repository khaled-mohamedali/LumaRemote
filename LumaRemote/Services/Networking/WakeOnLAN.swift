import Foundation
import Network

/// Wake-on-LAN for LG webOS ("Mobile TV On" / "Turn on via Wi-Fi").
///
/// Limitations, stated plainly:
/// - The TV setting *Settings › All Settings › General › Mobile TV On › Turn on via
///   Wi-Fi* must be enabled, otherwise the network card sleeps with the TV.
/// - iOS only lets apps send *broadcast* UDP if Apple grants the Multicast Networking
///   entitlement. Without it the broadcast attempt fails and we fall back to sending
///   the packet straight to the TV's IP, which works as long as your router still
///   remembers the TV (usually for a while after it was switched off).
enum WakeOnLAN {
    struct Report: Sendable {
        var delivered: [String] = []
        var failed: [String] = []
        var anyDelivered: Bool { !delivered.isEmpty }
    }

    /// Parses "AA:BB:CC:DD:EE:FF", "aa-bb-cc-dd-ee-ff" or "aabbccddeeff".
    nonisolated static func parseMAC(_ string: String) -> [UInt8]? {
        let hex = string.filter { $0.isHexDigit }
        let separators = string.filter { !$0.isHexDigit }
        guard hex.count == 12, separators.allSatisfy({ $0 == ":" || $0 == "-" || $0 == "." || $0 == " " }) else {
            return nil
        }
        var bytes: [UInt8] = []
        var index = hex.startIndex
        for _ in 0..<6 {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        return bytes
    }

    nonisolated static func magicPacket(mac: [UInt8]) -> Data {
        var data = Data(repeating: 0xFF, count: 6)
        for _ in 0..<16 { data.append(contentsOf: mac) }
        return data
    }

    static func wake(macAddresses: [String], tvHost: String) async -> Report {
        var report = Report()
        let packets = macAddresses.compactMap(parseMAC).map(magicPacket)
        guard !packets.isEmpty else { return report }

        var targets = ["255.255.255.255"]
        if let iface = LocalInterface.current() { targets.append(iface.broadcast.description) }
        targets.append(tvHost)

        for target in targets {
            var ok = false
            for port in [9, 7] {
                for packet in packets {
                    for _ in 0..<3 {
                        if await send(packet, to: target, port: port) == nil { ok = true }
                    }
                }
            }
            if ok { report.delivered.append(target) } else { report.failed.append(target) }
        }
        return report
    }

    /// Returns nil on success or an error description.
    private static func send(_ data: Data, to host: String, port: Int) async -> String? {
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else { return "bad port" }
        let connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .udp)
        connection.start(queue: .main)
        let result: String? = await withCheckedContinuation { continuation in
            let once = ResumeOnce<String?>(continuation)
            connection.send(content: data, completion: .contentProcessed { error in
                let message = error?.localizedDescription
                Task { @MainActor in once.resume(message) }
            })
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                once.resume("timed out")
            }
        }
        connection.cancel()
        return result
    }
}
