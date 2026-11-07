import Foundation
import Observation
import UIKit

/// Owns the connection to one LG webOS TV: connecting, pairing, capability detection,
/// subscriptions, commands and reconnection. SwiftUI never talks to sockets directly —
/// it goes through `RemoteViewModel`, which calls this service.
@Observable
final class WebOSService {
    enum Phase: Equatable {
        case idle
        case connecting(String)
        case awaitingPairing(previousKeyRejected: Bool)
        case connected
        case reconnecting(attempt: Int)
        case tvOff
        case failed(WebOSError)

        var isConnected: Bool { self == .connected }
        var isBusy: Bool {
            switch self {
            case .connecting, .awaitingPairing, .reconnecting: return true
            default: return false
            }
        }
    }

    // MARK: Observable state

    private(set) var phase: Phase = .idle
    private(set) var device: SavedDevice?
    private(set) var endpoint: TVEndpoint?
    private(set) var info = TVInfo()
    private(set) var audio: AudioStatus?
    private(set) var foregroundAppID: String?
    private(set) var launchPoints: [LaunchPoint] = []
    private(set) var inputs: [ExternalInput] = []
    private(set) var channel: ChannelInfo?
    private(set) var powerState: String?
    private(set) var keyboardFocused: Bool?
    private(set) var appsLoaded = false
    private(set) var inputsLoaded = false
    let capabilities = CapabilityStore()

    // MARK: Dependencies & internals

    @ObservationIgnored private let store: DeviceStore
    @ObservationIgnored private let keychain: KeychainStore
    @ObservationIgnored private let network: NetworkMonitor
    @ObservationIgnored private var socket: SSAPSocket?
    @ObservationIgnored private var pointer: PointerInputSocket?
    @ObservationIgnored private var session: URLSession?
    @ObservationIgnored private var trust: TVTrustDelegate?
    @ObservationIgnored private var connectTask: Task<Void, Never>?
    @ObservationIgnored private var keepAliveTask: Task<Void, Never>?
    @ObservationIgnored private var reconnectTask: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var hasConnectedThisSession = false
    @ObservationIgnored private var expectingPowerOff = false
    @ObservationIgnored private var iconCache: [URL: UIImage] = [:]

    init(store: DeviceStore, keychain: KeychainStore, network: NetworkMonitor) {
        self.store = store
        self.keychain = keychain
        self.network = network
    }

    var isPaired: Bool { device.map { keychain.hasClientKey(for: $0.id) } ?? false }

    // MARK: - Connection lifecycle

    /// Connects (or reconnects) to `device`. Cancels any connection in progress.
    func connect(to device: SavedDevice) {
        let switching = self.device?.id != device.id
        teardown()
        if switching {
            resetTVState()
            hasConnectedThisSession = false
        }
        self.device = device
        generation += 1
        let gen = generation
        connectTask = Task { [weak self] in
            await self?.runConnect(generation: gen, isReconnect: false)
        }
    }

    /// Reconnects to the current device if we're not connected.
    func reconnectIfNeeded() {
        guard let device, !phase.isConnected, !phase.isBusy else { return }
        connect(to: device)
    }

    /// User-initiated disconnect (e.g. app going to background, switching TVs).
    func disconnect(resetState: Bool = false) {
        teardown()
        phase = .idle
        if resetState {
            resetTVState()
            hasConnectedThisSession = false
        }
    }

    func forgetPairing(for deviceID: UUID) {
        keychain.deleteClientKey(for: deviceID)
        if device?.id == deviceID { disconnect(resetState: true) }
    }

    private func teardown() {
        connectTask?.cancel(); connectTask = nil
        reconnectTask?.cancel(); reconnectTask = nil
        keepAliveTask?.cancel(); keepAliveTask = nil
        socket?.onUnexpectedClose = nil
        socket?.close(); socket = nil
        pointer?.onClose = nil
        pointer?.close(); pointer = nil
        session?.invalidateAndCancel(); session = nil
        trust = nil
        generation += 1
    }

    private func resetTVState() {
        info = TVInfo()
        audio = nil
        foregroundAppID = nil
        launchPoints = []
        inputs = []
        channel = nil
        powerState = nil
        keyboardFocused = nil
        appsLoaded = false
        inputsLoaded = false
        endpoint = nil
        iconCache.removeAll()
        capabilities.reset()
    }

    private func runConnect(generation gen: Int, isReconnect: Bool) async {
        guard var device else { return }
        if !isReconnect { phase = .connecting("Looking for your TV…") }
        do {
            guard IPv4(device.host) != nil else { throw WebOSError.invalidAddress(device.host) }
            if network.definitelyOffline { throw WebOSError.notOnWiFi }

            let chosen = try await openFirstWorkingEndpoint(for: device, generation: gen)
            guard gen == generation else { return }
            endpoint = chosen

            phase = .connecting("Pairing…")
            let manifest = try await registerWithFallback(device: device, endpoint: chosen, generation: gen)
            guard gen == generation else { return }

            device.lastWorkingEndpoint = chosen
            device.registrationManifest = manifest.rawValue
            device.lastConnected = Date()
            if device.certificateFingerprint == nil, chosen.secure {
                device.certificateFingerprint = trust?.observedFingerprint
            }
            self.device = device
            store.upsert(device)

            phase = .connected
            hasConnectedThisSession = true
            expectingPowerOff = false
            Log.service.info("connected via \(chosen.label, privacy: .public)")

            await loadTVState(generation: gen)
            startKeepAlive(generation: gen)
        } catch {
            guard gen == generation, !Task.isCancelled else { return }
            let failure = (error as? WebOSError) ?? .protocolViolation(error.localizedDescription)
            Log.service.error("connect failed: \(failure.localizedDescription, privacy: .public)")
            teardown()
            if isReconnect || (hasConnectedThisSession && !failure.isTerminal) {
                scheduleReconnect()
            } else {
                phase = expectingPowerOff ? .tvOff : .failed(failure)
            }
        }
    }

    /// Tries each candidate endpoint: a fast TCP probe, then a WebSocket `hello`.
    private func openFirstWorkingEndpoint(for device: SavedDevice, generation gen: Int) async throws -> TVEndpoint {
        var lastError = WebOSError.timedOut(host: device.host)
        for candidate in device.candidateEndpoints() {
            guard gen == generation else { throw CancellationError() }
            switch await TCPProbe.probe(host: device.host, port: candidate.port) {
            case .open: break
            case .localNetworkDenied: throw WebOSError.localNetworkDenied
            case .refused: lastError = .connectionRefused(host: device.host, port: candidate.port); continue
            case .timeout: lastError = .timedOut(host: device.host); continue
            case .unreachable: lastError = .hostUnreachable(host: device.host); continue
            }
            do {
                try await openSocket(device: device, endpoint: candidate)
                return candidate
            } catch WebOSError.certificateChanged {
                throw WebOSError.certificateChanged
            } catch {
                Log.service.info("endpoint \(candidate.label, privacy: .public) failed")
                closeSocketOnly()
                lastError = (error as? WebOSError) ?? .notAWebOSTV
            }
        }
        throw lastError
    }

    private func openSocket(device: SavedDevice, endpoint: TVEndpoint) async throws {
        guard let url = endpoint.url(host: device.host) else { throw WebOSError.invalidAddress(device.host) }
        let (session, trust) = TVSessionFactory.makeSession(host: device.host, pinnedFingerprint: device.certificateFingerprint)
        self.session = session
        self.trust = trust
        let socket = SSAPSocket(url: url, session: session)
        self.socket = socket
        socket.start()

        do {
            try await socket.send(SSAPRequest(type: "hello", id: "hello", uri: nil, payload: [:]))
            let hello = try await socket.awaitMessage(id: "hello", timeout: .seconds(5), what: "hello")
            if hello.type == "hello" { info.applyHello(hello.payload) }
        } catch WebOSError.requestTimedOut {
            // Some older firmware ignores `hello`; the socket is open, so carry on.
            guard socket.isOpen else { throw WebOSError.notAWebOSTV }
        } catch {
            if trust.detectedMismatch { throw WebOSError.certificateChanged }
            throw error
        }

        // Newer firmware only answers getSystemInfo before registration.
        if let reply = try? await socket.request(SSAPEndpoint.systemInfo.uri, timeout: .seconds(3)), !reply.isError {
            info.applySystemInfo(reply.payload)
        }
    }

    private func closeSocketOnly() {
        socket?.onUnexpectedClose = nil
        socket?.close(); socket = nil
        session?.invalidateAndCancel(); session = nil
        trust = nil
    }

    // MARK: - Pairing

    private func registerWithFallback(device: SavedDevice, endpoint: TVEndpoint, generation gen: Int) async throws -> SSAPRegistration.Manifest {
        var order: [SSAPRegistration.Manifest] = [.current, .legacySigned]
        if let saved = device.registrationManifest.flatMap(SSAPRegistration.Manifest.init(rawValue:)) {
            order.removeAll { $0 == saved }
            order.insert(saved, at: 0)
        }
        var lastError: WebOSError = .pairingFailed("unknown")
        for (index, manifest) in order.enumerated() {
            if index > 0 {
                // The TV may close the socket after rejecting a manifest; start clean.
                closeSocketOnly()
                try await openSocket(device: device, endpoint: endpoint)
            }
            do {
                try await register(device: device, manifest: manifest)
                return manifest
            } catch WebOSError.pairingFailed(let reason) {
                guard gen == generation else { throw CancellationError() }
                lastError = .pairingFailed(reason)
                continue
            }
        }
        throw lastError
    }

    private func register(device: SavedDevice, manifest: SSAPRegistration.Manifest) async throws {
        guard let socket else { throw WebOSError.notConnected }
        let storedKey = keychain.clientKey(for: device.id)
        try await socket.send(SSAPRegistration.message(clientKey: storedKey, manifest: manifest))

        var reply = try await socket.awaitMessage(id: "register_0", timeout: .seconds(10), what: "pairing")
        if reply.type == "response", reply.payload?["pairingType"]?.string == "PROMPT" {
            // The TV is showing its "allow this device?" prompt. If we sent a key, the
            // TV didn't recognise it (e.g. after a factory reset) and asks again.
            phase = .awaitingPairing(previousKeyRejected: storedKey != nil)
            do {
                reply = try await socket.awaitMessage(id: "register_0", timeout: .seconds(60), what: "pairing")
            } catch WebOSError.requestTimedOut {
                throw WebOSError.pairingTimedOut
            } catch WebOSError.connectionLost {
                throw WebOSError.pairingRejected
            }
        }

        switch reply.type {
        case "registered":
            guard let key = reply.payload?["client-key"]?.string, !key.isEmpty else {
                throw WebOSError.pairingFailed("the TV didn’t return a pairing key")
            }
            if key != storedKey { keychain.setClientKey(key, for: device.id) }
        case "error":
            let text = reply.errorDescription.lowercased()
            if text.contains("denied") || text.contains("reject") || text.contains("cancel") || text.contains("403") {
                throw WebOSError.pairingRejected
            }
            throw WebOSError.pairingFailed(reply.errorDescription)
        default:
            throw WebOSError.pairingFailed("unexpected reply “\(reply.type)”")
        }
        socket.onUnexpectedClose = { [weak self] _ in self?.handleUnexpectedClose() }
    }

    // MARK: - Capability detection & subscriptions

    private func loadTVState(generation gen: Int) async {
        guard let socket else { return }

        if let reply = try? await socket.request(SSAPEndpoint.serviceList.uri), !reply.isError {
            let names = reply.payload?["services"]?.array?.compactMap { $0["name"]?.string } ?? []
            capabilities.setServices(names)
            info.services = names
        }
        if info.modelName == nil, let reply = try? await socket.request(SSAPEndpoint.systemInfo.uri), !reply.isError {
            info.applySystemInfo(reply.payload)
        }
        if let reply = try? await socket.request(SSAPEndpoint.softwareInfo.uri), !reply.isError {
            info.applySoftwareInfo(reply.payload)
        }
        if let reply = try? await socket.request(SSAPEndpoint.connectionInfo.uri), !reply.isError {
            info.applyConnectionInfo(reply.payload)
        }
        guard gen == generation else { return }
        persistLearnedInfo()

        await openPointerSocket()

        await track(.audioStatus) { [weak self] p in
            if let status = AudioStatus(p) { self?.audio = status }
        }
        await track(.foregroundApp) { [weak self] p in
            self?.foregroundAppID = p["appId"]?.string
        }
        await track(.powerState) { [weak self] p in
            guard let self, let state = p["state"]?.string else { return }
            self.powerState = state
            if ["Suspend", "Power Off", "Active Standby"].contains(state) { self.expectingPowerOff = true }
        }
        await track(.launchPoints, onFailure: { [weak self] in self?.appsLoaded = true }) { [weak self] p in
            self?.applyLaunchPoints(p)
        }
        await track(.externalInputs, onFailure: { [weak self] in self?.inputsLoaded = true }) { [weak self] p in
            guard let self else { return }
            if let devices = p["devices"]?.array {
                self.inputs = devices.compactMap(ExternalInput.init)
            }
            self.inputsLoaded = true
        }
        await track(.currentChannel) { [weak self] p in
            guard let self else { return }
            self.capabilities.setHasTuner(true)
            self.channel = ChannelInfo(number: p["channelNumber"]?.string, name: p["channelName"]?.string)
        }
        await track(.remoteKeyboard) { [weak self] p in
            if let focus = p["currentWidget"]?["focus"]?.bool { self?.keyboardFocused = focus }
        }
    }

    /// Subscribes and records capability from the first reply.
    private func track(_ endpoint: SSAPEndpoint, onFailure: (() -> Void)? = nil, update: @escaping (JSONValue) -> Void) async {
        guard let socket else { return }
        var first = true
        do {
            try await socket.subscribe(endpoint.uri) { [weak self] message in
                defer { first = false }
                if message.isError {
                    if first {
                        if message.isUnsupported { self?.capabilities.markUnsupported(endpoint) }
                        else if message.isPermissionDenied { self?.capabilities.markDenied(endpoint) }
                        onFailure?()
                    }
                    return
                }
                if let payload = message.payload { update(payload) }
            }
        } catch {
            onFailure?()
        }
    }

    private func applyLaunchPoints(_ p: JSONValue) {
        if let all = p["launchPoints"]?.array {
            launchPoints = all.compactMap(LaunchPoint.init)
        } else if let change = p["change"]?.string, let point = LaunchPoint(p) {
            launchPoints.removeAll { $0.id == point.id }
            if change != "removed" { launchPoints.append(point) }
        }
        appsLoaded = true
    }

    private func persistLearnedInfo() {
        guard var device else { return }
        device.modelName = info.modelName ?? device.modelName
        device.webOSVersion = info.productName ?? info.webOSVersion.map { "webOS \($0)" } ?? device.webOSVersion
        device.firmwareVersion = info.firmwareVersion ?? device.firmwareVersion
        let macs = info.macAddresses
        if !macs.isEmpty { device.macAddresses = macs }
        self.device = device
        store.upsert(device)
    }

    private func openPointerSocket() async {
        guard let socket, let session, let device else { return }
        do {
            let reply = try await socket.request(SSAPEndpoint.pointerInputSocket.uri)
            if reply.isError {
                if reply.isUnsupported { capabilities.markUnsupported(.pointerInputSocket) }
                capabilities.setPointerInput(false)
                return
            }
            guard let path = reply.payload?["socketPath"]?.string,
                  var components = URLComponents(string: path) else {
                capabilities.setPointerInput(false); return
            }
            // Some firmware reports ws://…:3000 even when only wss on 3001 is reachable;
            // follow the scheme and port of the main connection.
            if let main = endpoint, main.secure, components.scheme == "ws" {
                components.scheme = "wss"
                if components.port == 3000 || components.port == nil { components.port = main.port }
            }
            guard let url = components.url, url.host == device.host else {
                capabilities.setPointerInput(false); return
            }
            let pointer = PointerInputSocket(url: url, session: session)
            pointer.onClose = { [weak self] in self?.pointer = nil }
            pointer.start()
            self.pointer = pointer
            capabilities.setPointerInput(true)
        } catch {
            capabilities.setPointerInput(false)
        }
    }

    // MARK: - Keep-alive & reconnection

    private func startKeepAlive(generation gen: Int) {
        keepAliveTask?.cancel()
        keepAliveTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                guard let self, gen == self.generation, let socket = self.socket else { return }
                if await socket.ping() == false {
                    self.handleUnexpectedClose()
                    return
                }
            }
        }
    }

    private func handleUnexpectedClose() {
        guard phase.isConnected else { return }
        Log.service.info("connection lost")
        teardown()
        if expectingPowerOff {
            phase = .tvOff
        } else {
            scheduleReconnect()
        }
    }

    private func scheduleReconnect() {
        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            let delays: [Int] = [1, 2, 4, 8, 15]
            for (attempt, delay) in delays.enumerated() {
                guard let self, !Task.isCancelled else { return }
                self.phase = .reconnecting(attempt: attempt + 1)
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }
                if self.network.definitelyOffline { continue }
                self.generation += 1
                let gen = self.generation
                await self.runReconnectAttempt(generation: gen)
                if self.phase.isConnected || !self.phaseIsRetryable { return }
            }
            guard let self, !Task.isCancelled else { return }
            self.phase = .failed(self.network.definitelyOffline ? .notOnWiFi : .connectionLost)
        }
    }

    private var phaseIsRetryable: Bool {
        if case .failed(let e) = phase { return !e.isTerminal }
        return true
    }

    private func runReconnectAttempt(generation gen: Int) async {
        guard let device else { return }
        do {
            let chosen = try await openFirstWorkingEndpoint(for: device, generation: gen)
            endpoint = chosen
            _ = try await registerWithFallback(device: device, endpoint: chosen, generation: gen)
            phase = .connected
            await loadTVState(generation: gen)
            startKeepAlive(generation: gen)
        } catch {
            closeSocketOnly()
            let failure = (error as? WebOSError) ?? .connectionLost
            if failure.isTerminal || failure == .pairingTimedOut { phase = .failed(failure) }
        }
    }

    /// Called when Wi-Fi comes back.
    func networkRestored() {
        switch phase {
        case .failed, .reconnecting, .tvOff:
            if let device { connect(to: device) }
        default:
            break
        }
    }

    // MARK: - Commands

    func press(_ key: RemoteKey) async -> CommandOutcome {
        guard phase.isConnected, let socket else { return .failed(.notConnected) }

        if key == .power { return await powerOff() }

        if let endpoint = key.endpoint, capabilities.supports(endpoint) {
            var payload: JSONValue? = nil
            if key == .mute { payload = ["mute": .bool(!(audio?.muted ?? false))] }
            let outcome = await perform(endpoint, payload: payload, label: key.title, socket: socket)
            // If the API is missing on this firmware, fall back to the button route.
            if case .failed(.unsupported) = outcome, key.buttonName != nil {
                return await sendButton(key)
            }
            // Mute/volume state is updated by the TV's audio subscription, not guessed here.
            return outcome
        }
        return await sendButton(key)
    }

    private func sendButton(_ key: RemoteKey) async -> CommandOutcome {
        guard let name = key.buttonName else { return .failed(.unsupported(key.title)) }
        if pointer == nil || pointer?.isOpen == false {
            await openPointerSocket()
        }
        guard let pointer, pointer.isOpen else {
            return .failed(capabilities.pointerInput == false ? .unsupported("Button input") : .notConnected)
        }
        do {
            try await pointer.button(name)
            return .sent
        } catch {
            return .failed((error as? WebOSError) ?? .connectionLost)
        }
    }

    private func perform(_ endpoint: SSAPEndpoint, payload: JSONValue?, label: String, socket: SSAPSocket) async -> CommandOutcome {
        do {
            let reply = try await socket.request(endpoint.uri, payload: payload)
            if reply.isError {
                if reply.isUnsupported {
                    capabilities.markUnsupported(endpoint)
                    return .failed(.unsupported(label))
                }
                if reply.isPermissionDenied {
                    capabilities.markDenied(endpoint)
                    return .failed(.permissionDenied(label))
                }
                return .failed(.commandFailed(reply.errorDescription))
            }
            return .confirmed
        } catch {
            return .failed((error as? WebOSError) ?? .commandFailed(error.localizedDescription))
        }
    }

    /// Generic request for features outside `RemoteKey` (apps, inputs, text).
    func request(_ endpoint: SSAPEndpoint, payload: JSONValue? = nil, label: String) async -> CommandOutcome {
        guard phase.isConnected, let socket else { return .failed(.notConnected) }
        return await perform(endpoint, payload: payload, label: label, socket: socket)
    }

    /// The TV often closes the socket before replying to turnOff, so we don't treat a
    /// missing reply as failure — but we also don't claim success until the TV either
    /// confirms or drops the connection.
    private func powerOff() async -> CommandOutcome {
        guard let socket else { return .failed(.notConnected) }
        expectingPowerOff = true
        do {
            let reply = try await socket.request(SSAPEndpoint.turnOff.uri, timeout: .seconds(4))
            if reply.isError {
                expectingPowerOff = false
                return .failed(reply.isUnsupported ? .unsupported("Power off") : .commandFailed(reply.errorDescription))
            }
            return .confirmed
        } catch WebOSError.connectionLost {
            return .confirmed   // the TV hung up because it's turning off
        } catch {
            return .sent
        }
    }

    func launch(appID: String, title: String) async -> CommandOutcome {
        await request(.launch, payload: ["id": .string(appID)], label: title)
    }

    func switchInput(_ input: ExternalInput) async -> CommandOutcome {
        await request(.switchInput, payload: ["inputId": .string(input.id)], label: input.label)
    }

    func insertText(_ text: String) async -> CommandOutcome {
        await request(.insertText, payload: ["text": .string(text), "replace": false], label: "Keyboard")
    }

    func deleteCharacters(_ count: Int) async -> CommandOutcome {
        await request(.deleteCharacters, payload: ["count": .number(Double(count))], label: "Keyboard")
    }

    func sendEnter() async -> CommandOutcome {
        await request(.sendEnter, label: "Keyboard")
    }

    // MARK: - Wake

    func wake() async -> Result<WakeOnLAN.Report, WebOSError> {
        guard let device else { return .failure(.notConnected) }
        guard !device.macAddresses.isEmpty else {
            return .failure(.wakeFailed("the TV’s MAC address isn’t known yet. Connect once while the TV is on, or enter it in Power settings."))
        }
        let report = await WakeOnLAN.wake(macAddresses: device.macAddresses, tvHost: device.host)
        guard report.anyDelivered else {
            return .failure(.wakeFailed("iOS blocked the packet (\(report.failed.joined(separator: ", ")))."))
        }
        // Give the TV time to bring its network up, then try to reconnect.
        reconnectTask?.cancel()
        phase = .connecting("Waking your TV…")
        reconnectTask = Task { [weak self] in
            for _ in 0..<8 {
                try? await Task.sleep(for: .seconds(3))
                guard let self, !Task.isCancelled, !self.phase.isConnected else { return }
                if await TCPProbe.probe(host: device.host, port: (device.lastWorkingEndpoint ?? .secureDefault).port, timeout: .seconds(2)) == .open {
                    self.connect(to: device)
                    return
                }
            }
            self?.phase = .tvOff
        }
        return .success(report)
    }

    func updateDevice(_ device: SavedDevice) {
        store.upsert(device)
        if self.device?.id == device.id { self.device = device }
    }

    // MARK: - Icons (served by the TV, possibly over its self-signed HTTPS)

    func icon(for url: URL) async -> UIImage? {
        if let cached = iconCache[url] { return cached }
        guard let session, let host = device?.host, url.host == host else { return nil }
        guard let result = try? await session.data(from: url),
              (result.1 as? HTTPURLResponse)?.statusCode == 200,
              let image = UIImage(data: result.0) else { return nil }
        iconCache[url] = image
        return image
    }
}
