import Foundation

/// Outgoing SSAP frame: `{"type": ..., "id": ..., "uri": ..., "payload": {...}}`.
nonisolated struct SSAPRequest: Encodable, Sendable {
    var type: String
    var id: String
    var uri: String?
    var payload: JSONValue?

    func encoded() throws -> String {
        let data = try JSONEncoder().encode(self)
        guard let text = String(data: data, encoding: .utf8) else {
            throw WebOSError.protocolViolation("Could not encode request")
        }
        return text
    }
}

/// Incoming SSAP frame. `type` is one of `response`, `error`, `registered`, `hello`.
nonisolated struct SSAPMessage: Decodable, Sendable {
    var type: String
    var id: String?
    var error: String?
    var payload: JSONValue?

    static func decode(_ text: String) throws -> SSAPMessage {
        guard let data = text.data(using: .utf8) else {
            throw WebOSError.protocolViolation("Non-UTF8 frame")
        }
        return try JSONDecoder().decode(SSAPMessage.self, from: data)
    }

    var isError: Bool {
        if type == "error" { return true }
        if payload?["returnValue"]?.bool == false { return true }
        return false
    }

    /// The TV reports a missing API as `404 no such service or method`.
    var isUnsupported: Bool {
        let text = (error ?? payload?["errorText"]?.string ?? "").lowercased()
        return text.contains("404") || text.contains("no such service")
            || text.contains("unknown method") || text.contains("not supported")
    }

    var isPermissionDenied: Bool {
        let text = (error ?? payload?["errorText"]?.string ?? "").lowercased()
        return text.contains("401") || text.contains("insufficient permissions")
    }

    var errorDescription: String {
        error ?? payload?["errorText"]?.string ?? "The TV reported an error."
    }
}
