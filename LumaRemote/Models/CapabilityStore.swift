import Foundation
import Observation

/// Runtime capability detection. We never assume an API exists because of the TV's
/// model or webOS version; instead we record what the TV actually told us:
/// - `services`: the list returned by `api/getServiceList` (informational).
/// - `unsupported`: endpoints the TV answered with "404 no such service or method".
/// - `denied`: endpoints refused for lack of permission.
/// - `pointerInput`: whether the button/pointer socket could be opened.
/// Controls whose route is known to be unavailable are hidden from the UI.
@Observable
final class CapabilityStore {
    private(set) var services: [String] = []
    private(set) var unsupported: Set<SSAPEndpoint> = []
    private(set) var denied: Set<SSAPEndpoint> = []
    private(set) var pointerInput: Bool?   // nil = not yet known
    private(set) var hasTuner: Bool?

    func reset() {
        services = []
        unsupported = []
        denied = []
        pointerInput = nil
        hasTuner = nil
    }

    func setServices(_ names: [String]) { services = names.sorted() }
    func markUnsupported(_ e: SSAPEndpoint) { unsupported.insert(e) }
    func markDenied(_ e: SSAPEndpoint) { denied.insert(e) }
    func setPointerInput(_ available: Bool) { pointerInput = available }
    func setHasTuner(_ value: Bool) { hasTuner = value }

    func supports(_ e: SSAPEndpoint) -> Bool { !unsupported.contains(e) && !denied.contains(e) }

    /// Whether a key can be sent at all via either route.
    func canSend(_ key: RemoteKey) -> Bool {
        if let e = key.endpoint, supports(e) { return true }
        if key.buttonName != nil { return pointerInput != false }
        return false
    }
}
