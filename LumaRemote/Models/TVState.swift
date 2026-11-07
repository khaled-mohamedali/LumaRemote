import Foundation

/// What we've learned about the connected TV. Every field is optional because
/// different webOS versions expose different subsets.
nonisolated struct TVInfo: Equatable, Sendable {
    var modelName: String?
    var productName: String?        // e.g. "webOSTV 4.5"
    var firmwareVersion: String?    // e.g. "05.40.25"
    var webOSVersion: String?       // from hello: deviceOSReleaseVersion / deviceOSVersion
    var deviceOS: String?
    var receiverType: String?
    var country: String?
    var macWiFi: String?
    var macWired: String?
    var services: [String] = []

    mutating func applyHello(_ p: JSONValue?) {
        guard let p else { return }
        deviceOS = p["deviceOS"]?.string ?? deviceOS
        webOSVersion = p["deviceOSReleaseVersion"]?.string ?? p["deviceOSVersion"]?.string ?? webOSVersion
    }

    mutating func applySystemInfo(_ p: JSONValue?) {
        guard let p else { return }
        modelName = p["modelName"]?.string ?? modelName
        receiverType = p["receiverType"]?.string ?? receiverType
    }

    mutating func applySoftwareInfo(_ p: JSONValue?) {
        guard let p else { return }
        productName = p["product_name"]?.string ?? productName
        if modelName == nil { modelName = p["model_name"]?.string }
        if let major = p["major_ver"]?.string, let minor = p["minor_ver"]?.string {
            firmwareVersion = "\(major).\(minor)"
        }
        country = p["country"]?.string ?? country
    }

    mutating func applyConnectionInfo(_ p: JSONValue?) {
        guard let p else { return }
        macWiFi = p["wifiInfo"]?["macAddress"]?.string ?? macWiFi
        macWired = p["wiredInfo"]?["macAddress"]?.string ?? macWired
    }

    var macAddresses: [String] { [macWiFi, macWired].compactMap { $0 }.filter { !$0.isEmpty } }
}

nonisolated struct LaunchPoint: Identifiable, Hashable, Sendable {
    let id: String          // appId
    let title: String
    let iconURL: URL?

    init?(_ json: JSONValue) {
        guard let id = json["id"]?.string, let title = json["title"]?.string else { return nil }
        self.id = id
        self.title = title
        let icon = json["mediumLargeIcon"]?.string ?? json["largeIcon"]?.string ?? json["icon"]?.string
        self.iconURL = icon.flatMap(URL.init(string:))
    }
}

nonisolated struct ExternalInput: Identifiable, Hashable, Sendable {
    let id: String          // e.g. "HDMI_1"
    let label: String
    let appId: String?
    let connected: Bool
    let iconURL: URL?

    init?(_ json: JSONValue) {
        guard let id = json["id"]?.string else { return nil }
        self.id = id
        self.label = json["label"]?.string ?? id.replacingOccurrences(of: "_", with: " ")
        self.appId = json["appId"]?.string
        self.connected = json["connected"]?.bool ?? false
        self.iconURL = json["icon"]?.string.flatMap(URL.init(string:))
    }

    var symbol: String {
        let u = id.uppercased()
        if u.hasPrefix("HDMI") { return "cable.connector.horizontal" }
        if u.hasPrefix("AV") || u.hasPrefix("COMP") { return "rectangle.connected.to.line.below" }
        if u.hasPrefix("USB") { return "externaldrive" }
        return "tv"
    }
}

nonisolated struct AudioStatus: Equatable, Sendable {
    var volume: Int?
    var muted: Bool

    init?(_ p: JSONValue?) {
        guard let p else { return nil }
        // webOS ≤4.x: top-level fields. webOS 5+: nested `volumeStatus`.
        let nested = p["volumeStatus"]
        let mute = p["mute"]?.bool ?? p["muted"]?.bool ?? nested?["muteStatus"]?.bool
        let volume = p["volume"]?.int ?? nested?["volume"]?.int
        guard mute != nil || volume != nil else { return nil }
        self.muted = mute ?? false
        self.volume = volume
    }
}

nonisolated struct ChannelInfo: Equatable, Sendable {
    var number: String?
    var name: String?
}
