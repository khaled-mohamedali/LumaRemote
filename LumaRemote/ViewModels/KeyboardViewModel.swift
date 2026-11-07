import Foundation
import Observation

/// Sends text to the focused text field on the TV via the webOS IME service.
/// In live mode, each edit is mirrored as an insert or a delete; otherwise the text
/// is sent when the user taps Send.
@Observable
final class KeyboardViewModel {
    var text: String = "" {
        didSet { if liveTyping && !suppressMirror { mirror(from: oldValue, to: text) } }
    }

    @ObservationIgnored let service: WebOSService
    @ObservationIgnored let preferences: Preferences
    @ObservationIgnored let remote: RemoteViewModel
    /// Serialises sends so characters reach the TV in order.
    @ObservationIgnored private var queue: Task<Void, Never>?
    @ObservationIgnored private var suppressMirror = false

    init(service: WebOSService, preferences: Preferences, remote: RemoteViewModel) {
        self.service = service
        self.preferences = preferences
        self.remote = remote
    }

    var liveTyping: Bool { preferences.liveTyping }

    var isAvailable: Bool {
        service.phase.isConnected && service.capabilities.supports(.insertText)
    }

    /// nil = unknown (firmware didn't report focus).
    var tvFieldFocused: Bool? { service.keyboardFocused }

    private func mirror(from old: String, to new: String) {
        let common = old.commonPrefix(with: new)
        let deleteCount = old.count - common.count
        let insertion = String(new.dropFirst(common.count))
        enqueue {
            if deleteCount > 0 {
                let outcome = await self.service.deleteCharacters(deleteCount)
                if outcome.error != nil { return outcome }
            }
            if !insertion.isEmpty { return await self.service.insertText(insertion) }
            return .confirmed
        }
    }

    func sendAll() {
        let toSend = text
        guard !toSend.isEmpty else { return }
        enqueue { await self.service.insertText(toSend) }
        // Clearing must not mirror a delete back to the TV.
        clearLocally()
    }

    func enter() {
        enqueue { await self.service.sendEnter() }
        if liveTyping { clearLocally() }
    }

    func backspace() {
        enqueue { await self.service.deleteCharacters(1) }
    }

    func clearLocally() {
        suppressMirror = true
        text = ""
        suppressMirror = false
    }

    private func enqueue(_ work: @escaping @MainActor () async -> CommandOutcome) {
        let previous = queue
        queue = Task {
            await previous?.value
            let outcome = await work()
            if outcome.error != nil {
                self.remote.handle(outcome, for: "Keyboard")
            }
        }
    }
}
