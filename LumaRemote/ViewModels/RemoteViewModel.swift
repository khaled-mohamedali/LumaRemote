import Foundation
import Observation

/// What the SwiftUI remote, apps and inputs screens bind to. Holds no socket code —
/// it forwards to `WebOSService` and turns outcomes into UI feedback.
@Observable
final class RemoteViewModel {
    struct Toast: Identifiable, Equatable {
        enum Style { case info, error }
        let id = UUID()
        let message: String
        let style: Style
    }

    private(set) var toast: Toast?
    private(set) var lastSentKey: RemoteKey?

    @ObservationIgnored let service: WebOSService
    @ObservationIgnored let preferences: Preferences
    @ObservationIgnored private var toastTask: Task<Void, Never>?

    init(service: WebOSService, preferences: Preferences) {
        self.service = service
        self.preferences = preferences
    }

    // MARK: Derived state for views

    var phase: WebOSService.Phase { service.phase }
    var isConnected: Bool { service.phase.isConnected }
    var device: SavedDevice? { service.device }
    var capabilities: CapabilityStore { service.capabilities }
    var isMuted: Bool { service.audio?.muted ?? false }
    var volume: Int? { service.audio?.volume }

    var statusText: String {
        switch service.phase {
        case .idle: return service.device == nil ? "No TV" : "Not connected"
        case .connecting(let step): return step
        case .awaitingPairing: return "Accept on TV"
        case .connected: return "Connected"
        case .reconnecting: return "Reconnecting…"
        case .tvOff: return "TV is off"
        case .failed: return "Disconnected"
        }
    }

    /// Hide a key if the TV told us it can't do it, or if it's experimental and the
    /// user turned experimental keys off.
    func isVisible(_ key: RemoteKey) -> Bool {
        if key.isExperimental && !preferences.showExperimentalKeys { return false }
        return capabilities.canSend(key)
    }

    var hasMediaControls: Bool {
        [RemoteKey.play, .pause, .rewind, .fastForward].contains(where: isVisible)
    }

    var hasChannelControls: Bool { isVisible(.channelUp) || isVisible(.channelDown) }

    /// Netflix / Prime Video shortcuts appear only if the TV lists them as installed.
    var shortcutApps: [LaunchPoint] {
        let wanted = ["netflix", "amazon"]
        return wanted.compactMap { id in service.launchPoints.first { $0.id == id } }
    }

    // MARK: Actions

    func press(_ key: RemoteKey) {
        Haptics.tap(enabled: preferences.hapticsEnabled, strong: key == .power || key == .ok)
        Task {
            let outcome = await service.press(key)
            handle(outcome, for: key.title)
            if outcome != .failed(.notConnected) { lastSentKey = key }
        }
    }

    func launch(_ app: LaunchPoint) {
        launch(appID: app.id, title: app.title)
    }

    func launch(appID: String, title: String) {
        Haptics.tap(enabled: preferences.hapticsEnabled)
        Task {
            let outcome = await service.launch(appID: appID, title: title)
            handle(outcome, for: title, successMessage: "Opening \(title)")
        }
    }

    func switchInput(_ input: ExternalInput) {
        Haptics.tap(enabled: preferences.hapticsEnabled)
        Task {
            let outcome = await service.switchInput(input)
            handle(outcome, for: input.label, successMessage: "Switched to \(input.label)")
        }
    }

    func wake() {
        Haptics.tap(enabled: preferences.hapticsEnabled, strong: true)
        Task {
            switch await service.wake() {
            case .success(let report):
                showToast("Wake signal sent to \(report.delivered.joined(separator: ", ")). If “Turn on via Wi-Fi” is enabled, the TV should turn on.", .info)
            case .failure(let error):
                showToast(error.localizedDescription, .error)
                Haptics.error(enabled: preferences.hapticsEnabled)
            }
        }
    }

    func retry() {
        guard let device = service.device else { return }
        service.connect(to: device)
    }

    func handle(_ outcome: CommandOutcome, for label: String, successMessage: String? = nil) {
        switch outcome {
        case .confirmed:
            if let successMessage { showToast(successMessage, .info) }
        case .sent:
            break
        case .failed(let error):
            Haptics.error(enabled: preferences.hapticsEnabled)
            showToast(error.localizedDescription, .error)
        }
    }

    func dismissToast() {
        toastTask?.cancel()
        toast = nil
    }

    func showToast(_ message: String, _ style: Toast.Style) {
        toastTask?.cancel()
        toast = Toast(message: message, style: style)
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(style == .error ? 4 : 2.2))
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }
}
