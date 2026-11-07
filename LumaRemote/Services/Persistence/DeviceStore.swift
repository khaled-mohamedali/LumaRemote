import Foundation
import Observation

/// Saved TVs and the currently selected one, persisted as JSON in UserDefaults
/// (nothing sensitive here — pairing keys are in the Keychain).
@Observable
final class DeviceStore {
    private(set) var devices: [SavedDevice] = []
    var selectedID: UUID? {
        didSet { defaults.set(selectedID?.uuidString, forKey: Keys.selected) }
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let keychain: KeychainStore

    private enum Keys {
        static let devices = "devices.v1"
        static let selected = "devices.selected.v1"
    }

    init(defaults: UserDefaults = .standard, keychain: KeychainStore = KeychainStore()) {
        self.defaults = defaults
        self.keychain = keychain
        if let data = defaults.data(forKey: Keys.devices),
           let decoded = try? JSONDecoder().decode([SavedDevice].self, from: data) {
            devices = decoded
        }
        if let raw = defaults.string(forKey: Keys.selected), let id = UUID(uuidString: raw),
           devices.contains(where: { $0.id == id }) {
            selectedID = id
        } else {
            selectedID = devices.first?.id
        }
    }

    var selected: SavedDevice? { devices.first { $0.id == selectedID } }

    func device(_ id: UUID) -> SavedDevice? { devices.first { $0.id == id } }

    func device(host: String) -> SavedDevice? { devices.first { $0.host == host } }

    /// Inserts or replaces by id.
    func upsert(_ device: SavedDevice) {
        if let i = devices.firstIndex(where: { $0.id == device.id }) {
            guard devices[i] != device else { return }
            devices[i] = device
        } else {
            devices.append(device)
        }
        persist()
    }

    func remove(_ id: UUID) {
        devices.removeAll { $0.id == id }
        keychain.deleteClientKey(for: id)
        if selectedID == id { selectedID = devices.first?.id }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(devices) {
            defaults.set(data, forKey: Keys.devices)
        }
    }
}
