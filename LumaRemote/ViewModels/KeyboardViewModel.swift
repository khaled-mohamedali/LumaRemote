import Foundation
import Observation

/// Sends text to the focused text field on the TV via the webOS IME service.
/// In live mode, each edit is mirrored as an insert or a delete; otherwise the text
/// is sent when the user taps Send.
///
/// The IME only reaches text fields that use LG's system keyboard (browser, LG apps,
/// many web-based apps). YouTube, Netflix, Prime Video and others draw their own
/// keyboard, so text sent that way is accepted by the TV but never arrives. For those
/// apps we switch strategy: YouTube gets a direct search launch; the others get
/// navigation keys for their on-screen keyboard.
@Observable
final class KeyboardViewModel {
    var text: String = "" {
        didSet { if liveTyping && !suppressMirror { mirror(from: oldValue, to: text) } }
    }

    enum Target: Equatable {
        /// A system text field: typing works.
        case textField
        /// YouTube: search via a direct launch instead of typing.
        case youTube
        /// An app with its own on-screen keyboard that typed text can't reach.
        case ownKeyboard(appName: String)
    }

    /// Set when the user says "this app does use the TV keyboard" (cleared when the app
    /// on screen changes).
    private var typingForcedForApp: String?

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

    /// Decides how text can reach what's on screen:
    /// 1. YouTube → search launch.
    /// 2. The TV reports one of its own text fields is active → typing works, whatever the app.
    /// 3. LG's own apps and the browser → typing works.
    /// 4. Any other (third-party) app → it draws its own keyboard; typing can't reach it.
    var target: Target {
        let app = service.foregroundAppID ?? ""
        if app == WebOSService.youTubeAppID || app.hasPrefix("youtube.leanback") { return .youTube }
        if service.keyboardFocused == true || typingForcedForApp == app || Self.isLGSystemApp(app) {
            return .textField
        }
        let name = service.launchPoints.first { $0.id == app }?.title ?? "This app"
        return .ownKeyboard(appName: name)
    }

    nonisolated static func isLGSystemApp(_ appID: String) -> Bool {
        appID.isEmpty || appID.hasPrefix("com.webos.") || appID.hasPrefix("com.palm.")
            || appID.hasPrefix("com.lge.") || appID.hasPrefix("com.lg.")
    }

    /// Experimental: ask the app on screen to open search results for the typed text,
    /// using LG's voice-search launch intent (works for YouTube; untested elsewhere).
    func trySearchLaunch(appName: String) {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, let appID = service.foregroundAppID, !appID.isEmpty else { return }
        Haptics.tap(enabled: preferences.hapticsEnabled)
        Task {
            let outcome = await service.searchViaVoiceIntent(appID: appID, title: appName, query: query)
            remote.handle(outcome, for: appName,
                          successMessage: "Asked \(appName) to search for “\(query)”. If it just reopened, this app doesn’t support it — use the swipe pad.")
        }
    }

    /// For third-party apps that do use the TV's keyboard: send typed text anyway.
    func typeAnyway() {
        typingForcedForApp = service.foregroundAppID ?? ""
    }

    /// Searches YouTube for the typed text by relaunching it into search results.
    func searchYouTube(alternate: Bool = false) {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        Haptics.tap(enabled: preferences.hapticsEnabled)
        Task {
            let outcome = await service.searchYouTube(query, style: alternate ? .url : .voiceIntent)
            remote.handle(outcome, for: "YouTube", successMessage: "Searching YouTube for “\(query)”")
        }
    }

    private func mirror(from old: String, to new: String) {
        // Typing into YouTube/Netflix/… can't arrive; don't pretend it does.
        guard target == .textField else { return }
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
        guard !toSend.isEmpty, target == .textField else { return }
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
