import Foundation
import os

nonisolated enum Log {
    static let ws = Logger(subsystem: "com.lumaremote.app", category: "websocket")
    static let service = Logger(subsystem: "com.lumaremote.app", category: "webos")
    static let discovery = Logger(subsystem: "com.lumaremote.app", category: "discovery")
}

/// One SSAP WebSocket. Handles request/response correlation by `id`, long-lived
/// subscriptions, and buffering of replies that arrive before anyone awaits them.
/// It knows nothing about pairing or UI.
final class SSAPSocket {
    private let task: URLSessionWebSocketTask
    private var waiters: [String: (token: UUID, continuation: CheckedContinuation<SSAPMessage, Error>)] = [:]
    private var mailbox: [String: [SSAPMessage]] = [:]
    private var subscriptions: [String: (SSAPMessage) -> Void] = [:]
    private var receiveTask: Task<Void, Never>?
    private var counter = 0
    private(set) var isOpen = false

    /// Called once if the socket closes for any reason other than `close()`.
    var onUnexpectedClose: ((Error?) -> Void)?

    init(url: URL, session: URLSession) {
        task = session.webSocketTask(with: url)
        task.maximumMessageSize = 16 * 1024 * 1024   // app lists with icons can be large
    }

    func start() {
        guard !isOpen else { return }
        isOpen = true
        task.resume()
        receiveTask = Task { [weak self] in await self?.receiveLoop() }
    }

    func close() {
        shutdown(error: nil, notify: false)
    }

    // MARK: Sending

    func send(_ request: SSAPRequest) async throws {
        guard isOpen else { throw WebOSError.notConnected }
        let text = try request.encoded()
        if request.type != "register" {
            Log.ws.debug("→ \(request.type, privacy: .public) \(request.uri ?? "", privacy: .public)")
        } else {
            Log.ws.debug("→ register (payload redacted)")
        }
        do {
            try await task.send(.string(text))
        } catch {
            shutdown(error: error, notify: true)
            throw WebOSError.connectionLost
        }
    }

    func request(_ uri: String, payload: JSONValue? = nil, timeout: Duration = .seconds(6)) async throws -> SSAPMessage {
        let id = nextID("req")
        try await send(SSAPRequest(type: "request", id: id, uri: uri, payload: payload ?? [:]))
        return try await awaitMessage(id: id, timeout: timeout, what: uri)
    }

    /// Fire-and-forget request (used for power-off, whose reply is unreliable).
    func requestWithoutWaiting(_ uri: String, payload: JSONValue? = nil) async throws {
        try await send(SSAPRequest(type: "request", id: nextID("ff"), uri: uri, payload: payload ?? [:]))
    }

    /// Subscribes; every message for this subscription (including the first reply,
    /// which may be an error) is delivered to `handler`.
    @discardableResult
    func subscribe(_ uri: String, payload: JSONValue? = nil, handler: @escaping (SSAPMessage) -> Void) async throws -> String {
        let id = nextID("sub")
        subscriptions[id] = handler
        if let queued = mailbox.removeValue(forKey: id) { queued.forEach(handler) }
        try await send(SSAPRequest(type: "subscribe", id: id, uri: uri, payload: payload ?? [:]))
        return id
    }

    // MARK: Receiving

    /// Waits for the next message with `id`. Messages that arrived earlier are kept in
    /// a mailbox, so there's no race between sending and awaiting.
    func awaitMessage(id: String, timeout: Duration, what: String) async throws -> SSAPMessage {
        if var queued = mailbox[id], !queued.isEmpty {
            let first = queued.removeFirst()
            mailbox[id] = queued.isEmpty ? nil : queued
            return first
        }
        guard isOpen else { throw WebOSError.connectionLost }
        let token = UUID()
        return try await withCheckedThrowingContinuation { continuation in
            waiters[id] = (token, continuation)
            Task { [weak self] in
                try? await Task.sleep(for: timeout)
                self?.expire(id: id, token: token, what: what)
            }
        }
    }

    private func expire(id: String, token: UUID, what: String) {
        guard let waiter = waiters[id], waiter.token == token else { return }
        waiters[id] = nil
        waiter.continuation.resume(throwing: WebOSError.requestTimedOut(what))
    }

    private func receiveLoop() async {
        while isOpen {
            do {
                let message = try await task.receive()
                switch message {
                case .string(let text): handle(text)
                case .data(let data): if let text = String(data: data, encoding: .utf8) { handle(text) }
                @unknown default: break
                }
            } catch {
                shutdown(error: error, notify: true)
                return
            }
        }
    }

    private func handle(_ text: String) {
        guard let message = try? SSAPMessage.decode(text) else {
            Log.ws.error("← undecodable frame (\(text.count) bytes)")
            return
        }
        // `hello` replies are routed by type because firmware differs on echoing the id.
        let id = message.type == "hello" ? "hello" : (message.id ?? "")
        Log.ws.debug("← \(message.type, privacy: .public) id=\(id, privacy: .public)")

        if let handler = subscriptions[id] {
            handler(message)
        } else if let waiter = waiters.removeValue(forKey: id) {
            waiter.continuation.resume(returning: message)
        } else {
            mailbox[id, default: []].append(message)
            if mailbox.count > 64 { mailbox.removeAll() }   // never grow unbounded
        }
    }

    private func shutdown(error: Error?, notify: Bool) {
        guard isOpen else { return }
        isOpen = false
        receiveTask?.cancel()
        receiveTask = nil
        task.cancel(with: .goingAway, reason: nil)
        let pending = waiters
        waiters.removeAll()
        subscriptions.removeAll()
        mailbox.removeAll()
        for (_, waiter) in pending { waiter.continuation.resume(throwing: WebOSError.connectionLost) }
        if notify {
            if let error { Log.ws.info("socket closed: \(error.localizedDescription, privacy: .public)") }
            let callback = onUnexpectedClose
            onUnexpectedClose = nil
            callback?(error)
        }
    }

    /// WebSocket ping; false if the TV didn't answer.
    func ping(timeout: Duration = .seconds(5)) async -> Bool {
        guard isOpen else { return false }
        let task = self.task
        return await withCheckedContinuation { continuation in
            let once = ResumeOnce(continuation)
            task.sendPing { error in
                let ok = error == nil
                Task { @MainActor in once.resume(ok) }
            }
            Task { @MainActor in
                try? await Task.sleep(for: timeout)
                once.resume(false)
            }
        }
    }

    private func nextID(_ prefix: String) -> String {
        counter += 1
        return "\(prefix)_\(counter)"
    }
}

/// The secondary socket used for button presses. The TV gives us its URL via
/// `getPointerInputSocket`. Frames are plain text and are never acknowledged.
final class PointerInputSocket {
    private let task: URLSessionWebSocketTask
    private var receiveTask: Task<Void, Never>?
    private(set) var isOpen = false
    var onClose: (() -> Void)?

    init(url: URL, session: URLSession) {
        task = session.webSocketTask(with: url)
    }

    func start() {
        isOpen = true
        task.resume()
        // Nothing meaningful is ever received; the loop exists to notice closure.
        receiveTask = Task { [weak self] in
            guard let self else { return }
            while self.isOpen {
                do { _ = try await self.task.receive() } catch { self.markClosed(); return }
            }
        }
    }

    func button(_ name: String) async throws {
        guard isOpen else { throw WebOSError.notConnected }
        do {
            try await task.send(.string("type:button\nname:\(name)\n\n"))
        } catch {
            markClosed()
            throw WebOSError.connectionLost
        }
    }

    func close() {
        guard isOpen else { return }
        isOpen = false
        receiveTask?.cancel()
        task.cancel(with: .goingAway, reason: nil)
    }

    private func markClosed() {
        guard isOpen else { return }
        close()
        onClose?()
    }
}
