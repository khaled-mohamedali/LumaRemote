import Foundation
import Observation

/// Drives the device screen: saved TVs, discovery, manual entry and connection tests.
@Observable
final class DevicesViewModel {
    enum TestState: Equatable {
        case idle
        case testing
        case success(TVProber.Result)
        case failure(WebOSError)
    }

    // Manual entry form
    var manualHost = ""
    var manualName = ""
    var manualPort = ""
    var manualTransport: TransportPreference = .automatic
    var manualPairingMethod: PairingMethod = .pin
    private(set) var testState: TestState = .idle

    let discovery = DiscoveryService()

    @ObservationIgnored let store: DeviceStore
    @ObservationIgnored let service: WebOSService
    @ObservationIgnored let keychain: KeychainStore

    init(store: DeviceStore, service: WebOSService, keychain: KeychainStore) {
        self.store = store
        self.service = service
        self.keychain = keychain
    }

    var devices: [SavedDevice] { store.devices }
    var selectedID: UUID? { store.selectedID }

    func isPaired(_ device: SavedDevice) -> Bool { keychain.hasClientKey(for: device.id) }

    // MARK: Manual entry

    var trimmedHost: String { manualHost.trimmingCharacters(in: .whitespacesAndNewlines) }

    var hostValidationMessage: String? {
        guard !trimmedHost.isEmpty else { return nil }
        guard let ip = IPv4(trimmedHost) else { return "Enter an IPv4 address like 192.168.1.54." }
        if !ip.isPrivate { return "That isn’t a home-network address. TVs usually start with 192.168. or 10." }
        return nil
    }

    var portValue: Int? {
        let t = manualPort.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return nil }
        guard let p = Int(t), (1...65535).contains(p) else { return nil }
        return p
    }

    var portIsInvalid: Bool { !manualPort.trimmingCharacters(in: .whitespaces).isEmpty && portValue == nil }

    var canSubmitManual: Bool { IPv4(trimmedHost) != nil && !portIsInvalid }

    private func draftDevice() -> SavedDevice {
        var device = store.device(host: trimmedHost) ?? SavedDevice(name: "", host: trimmedHost)
        if !manualName.trimmingCharacters(in: .whitespaces).isEmpty {
            device.name = manualName.trimmingCharacters(in: .whitespaces)
        }
        device.customPort = portValue
        device.transport = manualTransport
        device.pairingMethod = manualPairingMethod
        return device
    }

    func testConnection() {
        guard canSubmitManual else {
            testState = .failure(.invalidAddress(trimmedHost))
            return
        }
        let device = draftDevice()
        testState = .testing
        Task {
            let result = await TVProber.identify(host: device.host, endpoints: device.candidateEndpoints())
            switch result {
            case .success(let info): testState = .success(info)
            case .failure(let error): testState = .failure(error)
            }
        }
    }

    /// Saves the manual entry and starts pairing.
    func saveManualAndConnect() {
        guard canSubmitManual else { return }
        var device = draftDevice()
        if case .success(let info) = testState, info.host == device.host {
            device.lastWorkingEndpoint = info.endpoint
            device.modelName = device.modelName ?? info.modelName
            if let v = info.webOSVersion { device.webOSVersion = device.webOSVersion ?? "webOS \(v)" }
        }
        resetForm()
        add(device)
    }

    func resetForm() {
        manualHost = ""
        manualName = ""
        manualPort = ""
        manualTransport = .automatic
        manualPairingMethod = .pin
        testState = .idle
    }

    // MARK: Discovery

    func add(_ found: DiscoveryService.FoundTV) {
        var device = store.device(host: found.host) ?? SavedDevice(name: "", host: found.host)
        device.lastWorkingEndpoint = found.endpoint
        device.modelName = device.modelName ?? found.modelName
        if let v = found.webOSVersion { device.webOSVersion = device.webOSVersion ?? "webOS \(v)" }
        add(device)
    }

    func isSaved(_ found: DiscoveryService.FoundTV) -> Bool { store.device(host: found.host) != nil }

    // MARK: Saved devices

    func add(_ device: SavedDevice) {
        store.upsert(device)
        select(device)
    }

    func select(_ device: SavedDevice) {
        store.selectedID = device.id
        service.connect(to: device)
    }

    func remove(_ device: SavedDevice) {
        if service.device?.id == device.id { service.disconnect(resetState: true) }
        store.remove(device.id)
        if let next = store.selected { service.connect(to: next) }
    }

    func update(_ device: SavedDevice) {
        service.updateDevice(device)
    }

    func forgetPairing(_ device: SavedDevice) {
        service.forgetPairing(for: device.id)
    }

    func resetTrust(_ device: SavedDevice) {
        var d = device
        d.certificateFingerprint = nil
        service.updateDevice(d)
    }
}
