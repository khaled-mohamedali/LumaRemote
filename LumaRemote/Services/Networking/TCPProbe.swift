import Foundation
import Network

/// Resumes a continuation at most once, whichever of (result, timeout) comes first.
final class ResumeOnce<T: Sendable> {
    private var continuation: CheckedContinuation<T, Never>?
    init(_ continuation: CheckedContinuation<T, Never>) { self.continuation = continuation }
    func resume(_ value: T) {
        continuation?.resume(returning: value)
        continuation = nil
    }
    var isDone: Bool { continuation == nil }
}

/// A quick TCP reachability check. Using Network.framework (rather than letting the
/// WebSocket time out) gives precise diagnostics: refused vs. silent vs. the user
/// having denied Local Network access.
enum TCPProbe {
    nonisolated enum Result: Sendable, Equatable {
        case open
        case refused
        case timeout
        case localNetworkDenied
        case unreachable(String)
    }

    static func probe(host: String, port: Int, timeout: Duration = .seconds(3)) async -> Result {
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(clamping: port)) else {
            return .unreachable("invalid port")
        }
        let params = NWParameters.tcp
        params.prohibitedInterfaceTypes = [.cellular]
        let connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: params)

        let result: Result = await withCheckedContinuation { continuation in
            let once = ResumeOnce(continuation)
            connection.stateUpdateHandler = { state in
                Task { @MainActor in
                    switch state {
                    case .ready:
                        once.resume(.open)
                    case .waiting(let error):
                        if connection.currentPath?.unsatisfiedReason == .localNetworkDenied {
                            once.resume(.localNetworkDenied)
                        } else if case .posix(let code) = error, code == .ECONNREFUSED {
                            once.resume(.refused)
                        }
                        // Otherwise keep waiting until the timeout fires.
                    case .failed(let error):
                        if case .posix(let code) = error, code == .ECONNREFUSED {
                            once.resume(.refused)
                        } else {
                            once.resume(.unreachable(error.localizedDescription))
                        }
                    default:
                        break
                    }
                }
            }
            connection.start(queue: .main)
            Task { @MainActor in
                try? await Task.sleep(for: timeout)
                once.resume(.timeout)
            }
        }
        connection.stateUpdateHandler = nil
        connection.cancel()
        return result
    }
}
