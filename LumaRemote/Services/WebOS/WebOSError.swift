import Foundation

/// Every failure surfaced to the UI. Messages are written for the person holding the
/// phone, not for a developer.
nonisolated enum WebOSError: Error, Sendable, Equatable, LocalizedError {
    case invalidAddress(String)
    case notOnWiFi
    case localNetworkDenied
    case hostUnreachable(host: String)
    case connectionRefused(host: String, port: Int)
    case timedOut(host: String)
    case notAWebOSTV
    case certificateChanged
    case pairingRejected
    case pairingTimedOut
    case pairingFailed(String)
    case notConnected
    case unsupported(String)
    case permissionDenied(String)
    case commandFailed(String)
    case requestTimedOut(String)
    case connectionLost
    case protocolViolation(String)
    case wakeFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidAddress(let a):
            return "“\(a)” isn’t a valid IP address. It should look like 192.168.1.54."
        case .notOnWiFi:
            return "Your iPhone isn’t connected to Wi-Fi. Join the same network as your TV."
        case .localNetworkDenied:
            return "Luma Remote isn’t allowed to access your local network. Turn it on in Settings › Privacy & Security › Local Network."
        case .hostUnreachable(let host):
            return "Couldn’t reach \(host). Check the TV is on and connected to the same Wi-Fi network."
        case .connectionRefused(let host, let port):
            return "The device at \(host) refused connections on port \(port). Make sure it’s your LG TV and that “LG Connect Apps” is enabled."
        case .timedOut(let host):
            return "\(host) didn’t respond. The TV may be off, asleep, or on a different network."
        case .notAWebOSTV:
            return "That device answered, but it doesn’t look like an LG webOS TV."
        case .certificateChanged:
            return "The TV’s security certificate has changed since you paired. If you updated the TV’s firmware, reset trust for this TV in Devices."
        case .pairingRejected:
            return "The pairing request was declined on the TV. Try again and choose “Accept” with your TV remote."
        case .pairingTimedOut:
            return "No response to the pairing prompt. Try again and accept the request on your TV."
        case .pairingFailed(let reason):
            return "Pairing failed: \(reason)"
        case .notConnected:
            return "Not connected to your TV."
        case .unsupported(let what):
            return "\(what) isn’t supported by this TV’s firmware."
        case .permissionDenied(let what):
            return "The TV didn’t grant permission for \(what). Re-pairing may help."
        case .commandFailed(let reason):
            return "The TV reported an error: \(reason)"
        case .requestTimedOut(let what):
            return "The TV didn’t confirm \(what) in time."
        case .connectionLost:
            return "The connection to your TV was lost."
        case .protocolViolation(let detail):
            return "Unexpected response from the TV (\(detail))."
        case .wakeFailed(let detail):
            return "Couldn’t send the wake signal: \(detail)"
        }
    }

    /// Errors that mean "trying again won't help without user action".
    var isTerminal: Bool {
        switch self {
        case .pairingRejected, .certificateChanged, .localNetworkDenied, .invalidAddress, .notAWebOSTV:
            return true
        default:
            return false
        }
    }
}
