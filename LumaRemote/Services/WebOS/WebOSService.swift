import Foundation
import Observation
import UIKit

/// Owns the connection to one LG webOS TV: connecting, pairing, capability detection,
/// subscriptions, commands and reconnection. SwiftUI never talks to sockets directly —
/// it goes through `RemoteViewModel`, which calls this service.
@Observable
final class WebOSService {
    /// State of the "type the code shown on your TV" step.
    struct PinRequest: Equatable {
        var message: String?
        var verifying: Bool
        var previousKeyRejected: Bool
    }

    enum Phase: Equatable {
        case idle
        case connecting(String)
        case awaitingPairing(previousKeyRejected: Bool)
        case awaitingPin(PinRequest)
        case connected
        case reconnecting(attempt: Int)
        case tvOff
        case failed(WebOSError)

        var isConnected: Bool { self == .connected }
        var isBusy: Bool {
            switch self {
            case .connecting, .awaitingPairing, .awaitingPin, .reconnecting: return true
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
    /// True when code pairing was requested but this TV doesn't offer it, so the
    /// Accept prompt is used instead.
    private(set) var pinPairingUnavailable = false
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
    @ObservationIgnored private var iconTasks: [URL: Task<UIImage?, Never>] = [:]
    @ObservationIgnored private var iconFailures: Set<URL> = []
    @ObservationIgnored private var pinContinuation: CheckedContinuation<String?, Never>?

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
        pinContinuation?.resume(returning: nil); pinContinuation = nil
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
        iconTasks.values.forEach { $0.cancel() }
        iconTasks.removeAll()
        iconFailures.removeAll()
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

    /// Pairs using the TV's preferred method for this device. Order of attempts:
    /// 1. the chosen method (code by default) with the current manifest,
    /// 2. the same method with the legacy signed manifest,
    /// 3. for code pairing only: the Accept prompt, if the TV refused code pairing.
    /// A wrong code restarts registration so the TV shows a fresh code (max 3 tries).
    private func registerWithFallback(device: SavedDevice, endpoint: TVEndpoint, generation gen: Int) async throws -> SSAPRegistration.Manifest {
        var manifests: [SSAPRegistration.Manifest] = [.current, .legacySigned]
        if let saved = device.registrationManifest.flatMap(SSAPRegistration.Manifest.init(rawValue:)) {
            manifests.removeAll { $0 == saved }
            manifests.insert(saved, at: 0)
        }
        var method = device.effectivePairingMethod
        pinPairingUnavailable = false
        if method == .pin, info.supportsPinPairing == false {
            method = .prompt
            pinPairingUnavailable = true
        }
        var attempts: [(manifest: SSAPRegistration.Manifest, method: PairingMethod)] = manifests.map { ($0, method) }
        if method == .pin { attempts.append((manifests[0], .prompt)) }

        var lastError: WebOSError = .pairingFailed("unknown")
        var index = 0
        var needsFreshSocket = false
        var wrongCodes = 0
        var pinMessage: String?
        while index < attempts.count {
            let attempt = attempts[index]
            if needsFreshSocket {
                // The TV may close the socket after a failed registration; start clean.
                closeSocketOnly()
                try await openSocket(device: device, endpoint: endpoint)
            }
            needsFreshSocket = true
            if attempt.method == .prompt && method == .pin { pinPairingUnavailable = true }
            do {
                try await register(device: device, manifest: attempt.manifest, method: attempt.method, pinMessage: pinMessage)
                return attempt.manifest
            } catch WebOSError.pinIncorrect {
                guard gen == generation else { throw CancellationError() }
                wrongCodes += 1
                guard wrongCodes < 3 else { throw WebOSError.pinIncorrect }
                pinMessage = "That code didn’t match. Your TV is now showing a new one."
                // Same attempt again on a fresh socket → the TV shows a new code.
            } catch WebOSError.pairingFailed(let reason) {
                guard gen == generation else { throw CancellationError() }
                lastError = .pairingFailed(reason)
                index += 1
            }
        }
        throw lastError
    }

    private func register(device: SavedDevice, manifest: SSAPRegistration.Manifest,
                          method: PairingMethod, pinMessage: String?) async throws {
        guard let socket else { throw WebOSError.notConnected }
        let storedKey = keychain.clientKey(for: device.id)
        try await socket.send(SSAPRegistration.message(clientKey: storedKey, manifest: manifest, pairingType: method.wireValue))

        // With a valid stored key the TV answers `registered` straight away, whatever
        // the pairing type. Otherwise it first says which kind of pairing it started.
        var reply = try await socket.awaitMessage(id: "register_0", timeout: .seconds(10), what: "pairing")
        var sentPin = false
        if reply.type == "response" {
            let started = reply.payload?["pairingType"]?.string?.uppercased() ?? ""
            if started == "PROMPT" {
                // The TV is showing "Allow this device?". If we sent a key, the TV didn't
                // recognise it (e.g. after a factory reset) and asks again.
                phase = .awaitingPairing(previousKeyRejected: storedKey != nil)
                do {
                    reply = try await socket.awaitMessage(id: "register_0", timeout: .seconds(60), what: "pairing")
                } catch WebOSError.requestTimedOut {
                    throw WebOSError.pairingTimedOut
                } catch WebOSError.connectionLost {
                    throw WebOSError.pairingRejected
                }
            } else if started.contains("PIN") || started == "COMBINED" {
                reply = try await exchangePin(socket: socket, previousKeyRejected: storedKey != nil, message: pinMessage)
                sentPin = true
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
            if sentPin { throw WebOSError.pinIncorrect }
            throw WebOSError.pairingFailed(reply.errorDescription)
        default:
            throw WebOSError.pairingFailed("unexpected reply “\(reply.type)”")
        }
        socket.onUnexpectedClose = { [weak self] _ in self?.handleUnexpectedClose() }
    }

    /// Code pairing: wait for the user to type the code shown on the TV, send it with
    /// `pairing/setPin`, then wait for the TV's `registered` reply to the original
    /// register request.
    private func exchangePin(socket: SSAPSocket, previousKeyRejected: Bool, message: String?) async throws -> SSAPMessage {
        phase = .awaitingPin(PinRequest(message: message, verifying: false, previousKeyRejected: previousKeyRejected))
        guard let pin = await waitForPin() else { throw CancellationError() }

        do {
            let ack = try await socket.request(SSAPEndpoint.setPin.uri, payload: ["pin": .string(pin)], timeout: .seconds(8))
            if ack.isError {
                if ack.isUnsupported { throw WebOSError.pairingFailed("this TV doesn’t accept pairing codes") }
                throw WebOSError.pinIncorrect
            }
        } catch WebOSError.requestTimedOut {
            // Some firmware doesn't acknowledge setPin; the register reply below decides.
        }
        do {
            return try await socket.awaitMessage(id: "register_0", timeout: .seconds(10), what: "pairing")
        } catch WebOSError.requestTimedOut {
            throw WebOSError.pinIncorrect
        }
    }

    private func waitForPin() async -> String? {
        pinContinuation?.resume(returning: nil)
        return await withCheckedContinuation { continuation in
            pinContinuation = continuation
        }
    }

    /// Called by the UI with the code the user read off the TV.
    func submitPin(_ pin: String) {
        let digits = pin.filter(\.isNumber)
        guard !digits.isEmpty, case .awaitingPin(var request) = phase, !request.verifying,
              let continuation = pinContinuation else { return }
        pinContinuation = nil
        request.verifying = true
        request.message = nil
        phase = .awaitingPin(request)
        continuation.resume(returning: digits)
    }

    /// Starts pairing over (new code / new prompt), optionally switching method.
    func restartPairing(using method: PairingMethod? = nil) {
        guard var device else { return }
        if let method, device.pairingMethod != method {
            device.pairingMethod = method
            store.upsert(device)
        }
        connect(to: device)
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

    func launch(appID: String, title: String, params: JSONValue? = nil) async -> CommandOutcome {
        var payload: [String: JSONValue] = ["id": .string(appID)]
        if let params { payload["params"] = params }
        return await request(.launch, payload: .object(payload), label: title)
    }

    // MARK: - YouTube search

    /// YouTube (and Netflix, Prime…) draw their own on-screen keyboard, so text sent
    /// through the webOS IME never reaches their search box. YouTube can instead be
    /// (re)launched straight into search results.
    static let youTubeAppID = "youtube.leanback.v4"

    enum YouTubeSearchStyle { case voiceIntent, url }

    /// - `.voiceIntent`: the launch parameters LG's own voice search (ThinQ) sends to
    ///   YouTube: `contentTarget: {intent: "SearchContent", intentParam: query}`.
    /// - `.url`: the equivalent YouTube TV URL, as a fallback for app versions that
    ///   ignore the intent form.
    func searchYouTube(_ query: String, style: YouTubeSearchStyle = .voiceIntent) async -> CommandOutcome {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return .failed(.commandFailed("nothing to search for")) }
        let target: JSONValue
        switch style {
        case .voiceIntent:
            target = ["intent": "SearchContent", "intentParam": .string(q)]
        case .url:
            target = .string(Self.youTubeSearchURL(for: q))
        }
        return await launch(appID: Self.youTubeAppID, title: "YouTube", params: ["contentTarget": target])
    }

    /// Experimental: sends any app the same "SearchContent" launch intent LG's voice
    /// search uses. Whether an app honours it is up to the app; if it doesn't, the app
    /// usually just reopens. The TV only confirms the launch, not the search.
    func searchViaVoiceIntent(appID: String, title: String, query: String) async -> CommandOutcome {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return .failed(.commandFailed("nothing to search for")) }
        let intent: JSONValue = ["intent": "SearchContent", "intentParam": .string(q)]
        return await launch(appID: appID, title: title, params: ["contentTarget": intent])
    }

    nonisolated static func youTubeSearchURL(for query: String) -> String {
        var c = URLComponents(string: "https://www.youtube.com/tv")!
        c.queryItems = [
            URLQueryItem(name: "inApp", value: "true"),
            URLQueryItem(name: "vs", value: "9"),
            URLQueryItem(name: "va", value: "search"),
            URLQueryItem(name: "launch", value: "voice"),
            URLQueryItem(name: "launch", value: "search"),
            URLQueryItem(name: "vq", value: query),
        ]
        return (c.url?.absoluteString ?? "https://www.youtube.com/tv") + "#/"
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

    /// Loads an icon the TV advertised. Firmware often reports `http://<ip>:3000/…` even
    /// when only the secure port 3001 is open, sometimes uses a host other than the TV's
    /// IP, and some fields are bare paths. So for each advertised URL we try the same path
    /// on the TV's IP over the scheme/port of the live connection first, then the others.
    /// Results (including failures) are cached per TV connection and concurrent requests
    /// for the same icon share one download.
    func icon(for urls: [URL]) async -> UIImage? {
        guard let key = urls.first else { return nil }
        if let cached = iconCache[key] { return cached }
        if iconFailures.contains(key) { return nil }
        if let running = iconTasks[key] { return await running.value }
        guard let session, let host = device?.host else { return nil }

        let preferSecure = endpoint?.secure ?? true
        let securePort = endpoint?.secure == true ? (endpoint?.port ?? 3001) : 3001
        let plainPort = endpoint?.secure == false ? (endpoint?.port ?? 3000) : 3000
        var candidates: [URL] = []
        for url in urls {
            for c in Self.iconCandidates(for: url, tvHost: host, preferSecure: preferSecure,
                                         securePort: securePort, plainPort: plainPort)
            where !candidates.contains(c) { candidates.append(c) }
        }

        let task = Task { () -> UIImage? in
            for candidate in candidates {
                var request = URLRequest(url: candidate, timeoutInterval: 6)
                request.cachePolicy = .reloadIgnoringLocalCacheData
                guard let result = try? await session.data(for: request),
                      (result.1 as? HTTPURLResponse)?.statusCode == 200,
                      let image = UIImage(data: result.0) else { continue }
                return Self.downscaled(image, maxSide: 192)
            }
            return nil
        }
        iconTasks[key] = task
        let image = await task.value
        iconTasks[key] = nil
        guard device?.host == host else { return image }   // switched TVs meanwhile
        if let image {
            iconCache[key] = image
        } else {
            iconFailures.insert(key)
            Log.service.info("no icon could be loaded for \(key.lastPathComponent, privacy: .public)")
        }
        return image
    }

    nonisolated static func iconCandidates(for url: URL, tvHost: String, preferSecure: Bool,
                                           securePort: Int = 3001, plainPort: Int = 3000) -> [URL] {
        let parsed = URLComponents(url: url, resolvingAgainstBaseURL: false)
        var path = parsed?.percentEncodedPath ?? url.path
        guard !path.isEmpty else { return [] }
        if !path.hasPrefix("/") { path = "/" + path }
        let query = parsed?.percentEncodedQuery

        func make(_ scheme: String, _ port: Int) -> URL? {
            var c = URLComponents()
            c.scheme = scheme
            c.host = tvHost
            c.port = port
            c.percentEncodedPath = path
            c.percentEncodedQuery = query
            return c.url
        }
        var list: [URL] = []
        let secure = make("https", securePort)
        let plain = make("http", plainPort)
        list += preferSecure ? [secure, plain].compactMap { $0 } : [plain, secure].compactMap { $0 }
        // The URL exactly as advertised, if it points at the TV.
        if url.host == tvHost, let scheme = url.scheme, scheme.hasPrefix("http"), !list.contains(url) {
            list.insert(url, at: 1)
        }
        return list
    }

    nonisolated private static func downscaled(_ image: UIImage, maxSide: CGFloat) -> UIImage {
        let size = image.size
        let largest = max(size.width, size.height)
        guard largest > maxSide, largest > 0 else { return image }
        let scale = maxSide / largest
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        return image.preparingThumbnail(of: target) ?? image
    }
}
