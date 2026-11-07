import Foundation

/// How to reach the TV's SSAP WebSocket.
nonisolated struct TVEndpoint: Codable, Hashable, Sendable {
    var secure: Bool
    var port: Int

    static let secureDefault = TVEndpoint(secure: true, port: 3001)
    static let plainDefault = TVEndpoint(secure: false, port: 3000)

    func url(host: String) -> URL? {
        URL(string: "\(secure ? "wss" : "ws")://\(host):\(port)")
    }

    var label: String { "\(secure ? "wss" : "ws") · port \(port)" }
}

nonisolated enum TransportPreference: String, Codable, CaseIterable, Sendable, Identifiable {
    case automatic, secure, plain
    var id: String { rawValue }
    var title: String {
        switch self {
        case .automatic: return "Automatic"
        case .secure: return "Secure (wss)"
        case .plain: return "Plain (ws)"
        }
    }
}

/// A TV the user has added. The pairing key is NOT stored here — it lives in the
/// Keychain, keyed by `id`.
nonisolated struct SavedDevice: Codable, Identifiable, Hashable, Sendable {
    var id: UUID = UUID()
    var name: String
    var host: String
    var customPort: Int?
    var transport: TransportPreference = .automatic
    var lastWorkingEndpoint: TVEndpoint?
    var modelName: String?
    var webOSVersion: String?
    var firmwareVersion: String?
    var macAddresses: [String] = []
    var certificateFingerprint: String?
    var registrationManifest: String?
    var lastConnected: Date?

    var displayName: String { name.isEmpty ? (modelName.map { "LG \($0)" } ?? "LG TV") : name }

    /// Endpoints to try, most likely first. Firmware from roughly 2022 onward only
    /// accepts wss on 3001; older firmware only offers ws on 3000. We never assume —
    /// we try, then remember what worked.
    func candidateEndpoints() -> [TVEndpoint] {
        var list: [TVEndpoint] = []
        if let customPort {
            switch transport {
            case .secure: list = [TVEndpoint(secure: true, port: customPort)]
            case .plain: list = [TVEndpoint(secure: false, port: customPort)]
            case .automatic:
                list = [TVEndpoint(secure: true, port: customPort), TVEndpoint(secure: false, port: customPort)]
            }
        } else {
            switch transport {
            case .secure: list = [.secureDefault]
            case .plain: list = [.plainDefault]
            case .automatic: list = [.secureDefault, .plainDefault]
            }
        }
        if let last = lastWorkingEndpoint, list.contains(last) {
            list.removeAll { $0 == last }
            list.insert(last, at: 0)
        }
        return list
    }
}
