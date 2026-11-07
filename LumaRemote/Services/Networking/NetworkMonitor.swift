import Foundation
import Network
import Observation

/// Tracks whether the iPhone is on a local (Wi-Fi / Ethernet) network so we can tell
/// "your phone is off Wi-Fi" apart from "the TV is unreachable", and reconnect as soon
/// as Wi-Fi comes back.
@Observable
final class NetworkMonitor {
    private(set) var hasLocalNetwork: Bool = true
    private(set) var hasReportedPath = false
    /// Bumped each time the network comes back, so observers can react.
    private(set) var restoredCount = 0

    @ObservationIgnored private let monitor = NWPathMonitor()

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let local = path.status == .satisfied
                && (path.usesInterfaceType(.wifi) || path.usesInterfaceType(.wiredEthernet))
            guard let self else { return }
            Task { @MainActor in self.update(local: local) }
        }
        monitor.start(queue: .main)
    }

    private func update(local: Bool) {
        let wasLocal = hasLocalNetwork
        hasLocalNetwork = local
        if hasReportedPath && local && !wasLocal { restoredCount += 1 }
        hasReportedPath = true
    }

    /// True only when we positively know there's no Wi-Fi / Ethernet.
    var definitelyOffline: Bool { hasReportedPath && !hasLocalNetwork }
}
