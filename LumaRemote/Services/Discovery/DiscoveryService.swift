import Foundation
import Network
import Observation

/// Finds LG TVs on the local network. Two independent strategies:
///
/// 1. **Bonjour** (`_airplay._tcp`, `_hap._tcp`): many LG TVs advertise AirPlay or
///    HomeKit. Not every model does, which is why discovery failed for you before.
/// 2. **Subnet scan**: probes every address in your Wi-Fi /24 for the webOS ports
///    (3001, 3000). Needs only Local Network permission and works even when the TV
///    advertises nothing.
///
/// Every candidate is confirmed with a webOS `hello` before it is shown.
///
/// Not implemented: LG's SSDP discovery (`urn:lge-com:service:webos-second-screen:1`)
/// because iOS requires Apple's restricted Multicast Networking entitlement for it.
@Observable
final class DiscoveryService {
    struct FoundTV: Identifiable, Hashable, Sendable {
        var host: String
        var name: String
        var source: String
        var endpoint: TVEndpoint
        var webOSVersion: String?
        var modelName: String?
        var id: String { host }
    }

    private(set) var found: [FoundTV] = []
    private(set) var isScanning = false
    private(set) var progress: Double = 0
    private(set) var statusText: String?

    @ObservationIgnored private var browsers: [NWBrowser] = []
    @ObservationIgnored private var scanTask: Task<Void, Never>?
    @ObservationIgnored private var confirming: Set<String> = []

    func start() {
        stop()
        found = []
        isScanning = true
        progress = 0
        statusText = "Searching…"
        startBonjour()
        scanTask = Task { [weak self] in
            await self?.scanSubnet()
        }
    }

    func stop() {
        browsers.forEach { $0.cancel() }
        browsers = []
        scanTask?.cancel()
        scanTask = nil
        isScanning = false
        confirming = []
    }

    // MARK: Bonjour

    private func startBonjour() {
        for type in ["_airplay._tcp", "_hap._tcp"] {
            let browser = NWBrowser(for: .bonjourWithTXTRecord(type: type, domain: nil), using: .tcp)
            browser.browseResultsChangedHandler = { results, _ in
                let candidates: [(NWEndpoint, String, String)] = results.compactMap { result in
                    guard case .service(let name, _, _, _) = result.endpoint else { return nil }
                    var txt = ""
                    if case .bonjour(let record) = result.metadata {
                        txt = record.dictionary.values.joined(separator: " ")
                    }
                    let haystack = (name + " " + txt).lowercased()
                    guard haystack.contains("lg") || haystack.contains("webos") else { return nil }
                    return (result.endpoint, name, type)
                }
                Task { @MainActor [weak self] in
                    for (endpoint, name, type) in candidates { self?.resolve(endpoint, name: name, source: type) }
                }
            }
            browser.stateUpdateHandler = { state in
                if case .failed(let error) = state {
                    Log.discovery.info("bonjour failed: \(error.localizedDescription, privacy: .public)")
                }
            }
            browser.start(queue: .main)
            browsers.append(browser)
        }
    }

    /// Resolves a Bonjour service to an IPv4 address by opening a brief connection.
    private func resolve(_ endpoint: NWEndpoint, name: String, source: String) {
        let params = NWParameters.tcp
        if let ip = params.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options {
            ip.version = .v4
        }
        let connection = NWConnection(to: endpoint, using: params)
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                var host: String?
                if case .hostPort(let h, _) = connection.currentPath?.remoteEndpoint, case .ipv4(let address) = h {
                    host = "\(address)".components(separatedBy: "%").first
                }
                connection.cancel()
                Task { @MainActor [weak self] in
                    if let host { await self?.confirm(host: host, name: name, source: "Bonjour") }
                }
            case .failed, .waiting:
                connection.cancel()
            default:
                break
            }
        }
        connection.start(queue: .main)
    }

    // MARK: Subnet scan

    private func scanSubnet() async {
        guard let iface = LocalInterface.current() else {
            statusText = "Not connected to Wi-Fi."
            finishIfDone(scanned: true)
            return
        }
        let hosts = iface.scanHosts
        guard !hosts.isEmpty else { finishIfDone(scanned: true); return }
        let prefix = iface.address.description.split(separator: ".").prefix(3).joined(separator: ".")
        statusText = "Scanning \(prefix).x…"

        var completed = 0
        var openHosts: [String] = []
        let maxConcurrent = 32
        var pending = hosts.map(\.description)[...]

        await withTaskGroup(of: (String, Bool).self) { group in
            var inFlight = 0
            while true {
                // Keep at most `maxConcurrent` probes in flight.
                while inFlight < maxConcurrent, !pending.isEmpty {
                    let host = pending.removeFirst()
                    inFlight += 1
                    group.addTask {
                        for port in [3001, 3000] {
                            if await TCPProbe.probe(host: host, port: port, timeout: .milliseconds(900)) == .open {
                                return (host, true)
                            }
                        }
                        return (host, false)
                    }
                }
                guard let result = await group.next() else { break }
                inFlight -= 1
                if Task.isCancelled { group.cancelAll(); break }
                completed += 1
                progress = Double(completed) / Double(hosts.count)
                if result.1 { openHosts.append(result.0) }
            }
        }
        guard !Task.isCancelled else { return }
        for host in openHosts {
            await confirm(host: host, name: "LG webOS TV", source: "Network scan")
        }
        finishIfDone(scanned: true)
    }

    private func confirm(host: String, name: String, source: String) async {
        guard !found.contains(where: { $0.host == host }), !confirming.contains(host) else { return }
        confirming.insert(host)
        defer { confirming.remove(host) }
        let result = await TVProber.identify(host: host, endpoints: [.secureDefault, .plainDefault], probeTimeout: .seconds(2))
        guard case .success(let tv) = result, !found.contains(where: { $0.host == host }) else { return }
        let displayName = tv.modelName.map { "LG \($0)" } ?? (name.lowercased().contains("lg") ? name : "LG webOS TV")
        found.append(FoundTV(host: host, name: displayName, source: source, endpoint: tv.endpoint,
                             webOSVersion: tv.webOSVersion, modelName: tv.modelName))
        found.sort { (IPv4($0.host) ?? IPv4(0)) < (IPv4($1.host) ?? IPv4(0)) }
    }

    private func finishIfDone(scanned: Bool) {
        isScanning = false
        progress = 1
        statusText = found.isEmpty ? "No TVs found. You can enter the IP address manually." : nil
        // Bonjour keeps listening briefly in case the TV answers late.
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            self?.browsers.forEach { $0.cancel() }
            self?.browsers = []
        }
    }
}
