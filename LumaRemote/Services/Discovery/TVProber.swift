import Foundation

/// Tests whether an address is an LG webOS TV *without pairing*: TCP probe on each
/// candidate port, then a WebSocket `hello` (and, on firmware that allows it, a
/// pre-registration getSystemInfo for the model name). Used by "Test connection" and
/// to confirm discovery candidates.
enum TVProber {
    struct Result: Sendable, Equatable {
        var host: String
        var endpoint: TVEndpoint
        var webOSVersion: String?
        var modelName: String?
        var deviceUUID: String?
    }

    static func identify(host: String, endpoints: [TVEndpoint], probeTimeout: Duration = .seconds(3)) async -> Swift.Result<Result, WebOSError> {
        guard IPv4(host) != nil else { return .failure(.invalidAddress(host)) }
        var lastError = WebOSError.timedOut(host: host)

        for endpoint in endpoints {
            switch await TCPProbe.probe(host: host, port: endpoint.port, timeout: probeTimeout) {
            case .open: break
            case .localNetworkDenied: return .failure(.localNetworkDenied)
            case .refused: lastError = .connectionRefused(host: host, port: endpoint.port); continue
            case .timeout: lastError = .timedOut(host: host); continue
            case .unreachable: lastError = .hostUnreachable(host: host); continue
            }

            guard let url = endpoint.url(host: host) else { continue }
            let (session, _) = TVSessionFactory.makeSession(host: host, pinnedFingerprint: nil)
            let socket = SSAPSocket(url: url, session: session)
            socket.start()
            defer {
                socket.close()
                session.invalidateAndCancel()
            }
            do {
                try await socket.send(SSAPRequest(type: "hello", id: "hello", uri: nil, payload: [:]))
                let hello = try await socket.awaitMessage(id: "hello", timeout: .seconds(4), what: "hello")
                guard hello.type == "hello" || hello.id == "hello" else {
                    lastError = .notAWebOSTV
                    continue
                }
                var result = Result(host: host, endpoint: endpoint)
                result.webOSVersion = hello.payload?["deviceOSReleaseVersion"]?.string
                    ?? hello.payload?["deviceOSVersion"]?.string
                result.deviceUUID = hello.payload?["deviceUUID"]?.string
                if let info = try? await socket.request(SSAPEndpoint.systemInfo.uri, timeout: .seconds(2)), !info.isError {
                    result.modelName = info.payload?["modelName"]?.string
                }
                return .success(result)
            } catch {
                lastError = (error as? WebOSError) == .connectionLost ? .notAWebOSTV : ((error as? WebOSError) ?? .notAWebOSTV)
            }
        }
        return .failure(lastError)
    }
}
