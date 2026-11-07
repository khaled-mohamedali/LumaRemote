import Testing
import Foundation
@testable import LumaRemote

@Suite("SSAP protocol")
struct ProtocolTests {
    @Test func registerMessageCarriesKeyAndPromptPairing() throws {
        let msg = SSAPRegistration.message(clientKey: "abc123", manifest: .current)
        let json = try JSONDecoder().decode(JSONValue.self, from: Data(try msg.encoded().utf8))
        #expect(json["type"]?.string == "register")
        #expect(json["id"]?.string == "register_0")
        #expect(json["payload"]?["pairingType"]?.string == "PROMPT")
        #expect(json["payload"]?["client-key"]?.string == "abc123")
        #expect(json["payload"]?["forcePairing"]?.bool == false)
        #expect(json["payload"]?["manifest"]?["permissions"]?.array?.isEmpty == false)
    }

    @Test func firstRegistrationOmitsKey() throws {
        let msg = SSAPRegistration.message(clientKey: nil, manifest: .legacySigned)
        let json = try JSONDecoder().decode(JSONValue.self, from: Data(try msg.encoded().utf8))
        #expect(json["payload"]?["client-key"] == nil)
        #expect(json["payload"]?["manifest"]?["signed"]?["appId"]?.string == "com.lge.test")
        #expect(json["payload"]?["manifest"]?["signatures"]?.array?.first?["signature"]?.string?.hasSuffix("NQnAtw==") == true)
    }

    @Test func decodesRegisteredReply() throws {
        let m = try SSAPMessage.decode(#"{"type":"registered","id":"register_0","payload":{"client-key":"k"}}"#)
        #expect(m.type == "registered")
        #expect(m.payload?["client-key"]?.string == "k")
        #expect(!m.isError)
    }

    @Test func detectsUnsupportedAPI() throws {
        let m = try SSAPMessage.decode(#"{"type":"error","id":"req_3","error":"404 no such service or method","payload":{}}"#)
        #expect(m.isError)
        #expect(m.isUnsupported)
        #expect(!m.isPermissionDenied)
    }

    @Test func detectsPermissionError() throws {
        let m = try SSAPMessage.decode(#"{"type":"error","id":"req_4","error":"401 insufficient permissions","payload":""}"#)
        #expect(m.isPermissionDenied)
    }

    @Test func returnValueFalseIsError() throws {
        let m = try SSAPMessage.decode(#"{"type":"response","id":"req_5","payload":{"returnValue":false,"errorText":"oops"}}"#)
        #expect(m.isError)
        #expect(m.errorDescription == "oops")
    }

    @Test func parsesAudioStatusOldAndNewFirmware() {
        let old = AudioStatus(["mute": true, "volume": 12])
        #expect(old?.muted == true && old?.volume == 12)
        let new = AudioStatus(["volumeStatus": ["muteStatus": false, "volume": 30]])
        #expect(new?.muted == false && new?.volume == 30)
        #expect(AudioStatus(["returnValue": true]) == nil)
    }

    @Test func parsesLaunchPointsAndInputs() {
        let lp = LaunchPoint(["id": "youtube.leanback.v4", "title": "YouTube", "icon": "http://192.168.1.54:3000/x.png"])
        #expect(lp?.title == "YouTube")
        #expect(lp?.iconURL?.host == "192.168.1.54")
        let input = ExternalInput(["id": "HDMI_1", "label": "HDMI1", "connected": true, "appId": "com.webos.app.hdmi1"])
        #expect(input?.connected == true)
        #expect(input?.symbol == "cable.connector.horizontal")
    }

    @Test func iconURLsPreferWebURLsAndKeepAll() {
        let lp = LaunchPoint(["id": "netflix", "title": "Netflix",
                              "largeIcon": "/mnt/apps/netflix/large.png",
                              "icon": "http://192.168.1.54:3000/resources/abc/icon.png"])
        #expect(lp?.iconURLs.count == 2)
        #expect(lp?.iconURLs.first?.scheme == "http")
    }

    @Test func iconCandidatesRewriteToTVHostAndLivePort() {
        let advertised = URL(string: "http://localhost:3000/resources/abc/icon.png?v=1")!
        let urls = WebOSService.iconCandidates(for: advertised, tvHost: "192.168.1.54", preferSecure: true)
        #expect(urls.map(\.absoluteString) == [
            "https://192.168.1.54:3001/resources/abc/icon.png?v=1",
            "http://192.168.1.54:3000/resources/abc/icon.png?v=1",
        ])
        let onTV = URL(string: "http://192.168.1.54:3000/resources/abc/icon.png")!
        let plain = WebOSService.iconCandidates(for: onTV, tvHost: "192.168.1.54", preferSecure: false)
        #expect(plain.first?.absoluteString == "http://192.168.1.54:3000/resources/abc/icon.png")
        #expect(plain.count == 2)
        let bare = WebOSService.iconCandidates(for: URL(string: "resources/x.png")!, tvHost: "10.0.0.5", preferSecure: true)
        #expect(bare.first?.absoluteString == "https://10.0.0.5:3001/resources/x.png")
    }
}

@Suite("Networking helpers")
struct NetworkingTests {
    @Test func ipv4Parsing() {
        #expect(IPv4("192.168.1.54")?.description == "192.168.1.54")
        #expect(IPv4(" 10.0.0.2 ") != nil)
        #expect(IPv4("192.168.1") == nil)
        #expect(IPv4("192.168.1.256") == nil)
        #expect(IPv4("a.b.c.d") == nil)
        #expect(IPv4("192.168.1.54")?.isPrivate == true)
        #expect(IPv4("8.8.8.8")?.isPrivate == false)
    }

    @Test func subnetHostsAreClampedTo24() {
        let iface = LocalInterface(name: "en0", address: IPv4("192.168.1.20")!, netmask: IPv4("255.255.0.0")!)
        let hosts = iface.scanHosts
        #expect(hosts.count == 253)
        #expect(hosts.first?.description == "192.168.1.1")
        #expect(hosts.last?.description == "192.168.1.254")
        #expect(!hosts.contains(IPv4("192.168.1.20")!))
        #expect(iface.broadcast.description == "192.168.255.255")
    }

    @Test func magicPacket() {
        let mac = WakeOnLAN.parseMAC("a8:23:fe:01:02:03")
        #expect(mac == [0xA8, 0x23, 0xFE, 0x01, 0x02, 0x03])
        #expect(WakeOnLAN.parseMAC("A8-23-FE-01-02-03") != nil)
        #expect(WakeOnLAN.parseMAC("a823fe010203") != nil)
        #expect(WakeOnLAN.parseMAC("a8:23:fe:01:02") == nil)
        let packet = WakeOnLAN.magicPacket(mac: mac!)
        #expect(packet.count == 102)
        #expect(packet.prefix(6).allSatisfy { $0 == 0xFF })
    }

    @Test func endpointOrderPrefersLastWorking() {
        var d = SavedDevice(name: "", host: "192.168.1.54")
        #expect(d.candidateEndpoints() == [.secureDefault, .plainDefault])
        d.lastWorkingEndpoint = .plainDefault
        #expect(d.candidateEndpoints() == [.plainDefault, .secureDefault])
        d.transport = .secure
        #expect(d.candidateEndpoints() == [.secureDefault])
        d.customPort = 3555
        #expect(d.candidateEndpoints() == [TVEndpoint(secure: true, port: 3555)])
    }
}
