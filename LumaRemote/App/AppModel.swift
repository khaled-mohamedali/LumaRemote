import Foundation
import Observation

/// Composition root: creates the long-lived services and view models once and hands
/// them to SwiftUI through the environment.
@Observable
final class AppModel {
    let preferences: Preferences
    let deviceStore: DeviceStore
    let network: NetworkMonitor
    let service: WebOSService
    let remote: RemoteViewModel
    let devices: DevicesViewModel
    let keyboard: KeyboardViewModel
    let keychain: KeychainStore

    init() {
        let keychain = KeychainStore()
        let preferences = Preferences()
        let deviceStore = DeviceStore(keychain: keychain)
        let network = NetworkMonitor()
        let service = WebOSService(store: deviceStore, keychain: keychain, network: network)
        let remote = RemoteViewModel(service: service, preferences: preferences)
        self.keychain = keychain
        self.preferences = preferences
        self.deviceStore = deviceStore
        self.network = network
        self.service = service
        self.remote = remote
        self.devices = DevicesViewModel(store: deviceStore, service: service, keychain: keychain)
        self.keyboard = KeyboardViewModel(service: service, preferences: preferences, remote: remote)
    }

    /// Connect to the last-used TV at launch / when returning to the foreground.
    func activate() {
        guard let device = deviceStore.selected else { return }
        if service.device?.id != device.id {
            service.connect(to: device)
        } else {
            service.reconnectIfNeeded()
        }
    }

    /// iOS suspends sockets in the background; close cleanly and reconnect on return.
    func deactivate() {
        service.disconnect()
    }
}
