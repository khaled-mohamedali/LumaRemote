import Foundation

/// Every key Luma Remote can send, modeled on the LG AKB75675304 IR remote.
///
/// Routing rules:
/// - If an SSAP API exists (volume, mute, channel, media), we use it: the TV replies,
///   so success/failure is *confirmed*.
/// - Otherwise we send a button event over the TV's pointer-input socket
///   (`type:button\nname:X`). The TV never acknowledges these, so the UI only says
///   "sent", never "done".
/// - Keys marked `experimental` are on the IR remote but not documented for the
///   network API; some firmware ignores them. They can be hidden in Settings.
nonisolated enum RemoteKey: String, CaseIterable, Sendable, Identifiable {
    case power, home, back, ok, up, down, left, right
    case mute, volumeUp, volumeDown, channelUp, channelDown
    case settings, info, exit, guide, list, quickSettings
    case play, pause, stop, rewind, fastForward
    case red, green, yellow, blue
    case digit0, digit1, digit2, digit3, digit4, digit5, digit6, digit7, digit8, digit9, dash

    var id: String { rawValue }

    /// Name sent on the pointer-input socket, if any.
    var buttonName: String? {
        switch self {
        case .power: return nil
        case .home: return "HOME"
        case .back: return "BACK"
        case .ok: return "ENTER"
        case .up: return "UP"
        case .down: return "DOWN"
        case .left: return "LEFT"
        case .right: return "RIGHT"
        case .mute: return "MUTE"
        case .volumeUp: return "VOLUMEUP"
        case .volumeDown: return "VOLUMEDOWN"
        case .channelUp: return "CHANNELUP"
        case .channelDown: return "CHANNELDOWN"
        case .settings: return "MENU"
        case .info: return "INFO"
        case .exit: return "EXIT"
        case .guide: return "GUIDE"
        case .list: return "LIST"
        case .quickSettings: return "QMENU"
        case .play: return "PLAY"
        case .pause: return "PAUSE"
        case .stop: return "STOP"
        case .rewind: return "REWIND"
        case .fastForward: return "FASTFORWARD"
        case .red: return "RED"
        case .green: return "GREEN"
        case .yellow: return "YELLOW"
        case .blue: return "BLUE"
        case .dash: return "DASH"
        case .digit0, .digit1, .digit2, .digit3, .digit4, .digit5, .digit6, .digit7, .digit8, .digit9:
            return String(rawValue.last!)
        }
    }

    /// SSAP API that performs this key with a confirmed reply (preferred route).
    var endpoint: SSAPEndpoint? {
        switch self {
        case .power: return .turnOff
        case .volumeUp: return .volumeUp
        case .volumeDown: return .volumeDown
        case .mute: return .setMute
        case .channelUp: return .channelUp
        case .channelDown: return .channelDown
        case .play: return .play
        case .pause: return .pause
        case .stop: return .stop
        case .rewind: return .rewind
        case .fastForward: return .fastForward
        default: return nil
        }
    }

    /// Present on the IR remote but not part of the documented network key set.
    var isExperimental: Bool {
        switch self {
        case .guide, .list, .quickSettings: return true
        default: return false
        }
    }

    var title: String {
        switch self {
        case .power: return "Power"
        case .home: return "Home"
        case .back: return "Back"
        case .ok: return "OK"
        case .up: return "Up"
        case .down: return "Down"
        case .left: return "Left"
        case .right: return "Right"
        case .mute: return "Mute"
        case .volumeUp: return "Volume Up"
        case .volumeDown: return "Volume Down"
        case .channelUp: return "Channel Up"
        case .channelDown: return "Channel Down"
        case .settings: return "Settings"
        case .info: return "Info"
        case .exit: return "Exit"
        case .guide: return "Guide"
        case .list: return "List"
        case .quickSettings: return "Quick Settings"
        case .play: return "Play"
        case .pause: return "Pause"
        case .stop: return "Stop"
        case .rewind: return "Rewind"
        case .fastForward: return "Fast Forward"
        case .red: return "Red"
        case .green: return "Green"
        case .yellow: return "Yellow"
        case .blue: return "Blue"
        case .dash: return "–"
        default: return buttonName ?? rawValue
        }
    }

    var symbol: String {
        switch self {
        case .power: return "power"
        case .home: return "house.fill"
        case .back: return "arrow.uturn.backward"
        case .ok: return "circle"
        case .up: return "chevron.up"
        case .down: return "chevron.down"
        case .left: return "chevron.left"
        case .right: return "chevron.right"
        case .mute: return "speaker.slash.fill"
        case .volumeUp: return "plus"
        case .volumeDown: return "minus"
        case .channelUp: return "chevron.up"
        case .channelDown: return "chevron.down"
        case .settings: return "gearshape.fill"
        case .info: return "info.circle"
        case .exit: return "xmark.square"
        case .guide: return "list.bullet.rectangle"
        case .list: return "list.number"
        case .quickSettings: return "slider.horizontal.3"
        case .play: return "play.fill"
        case .pause: return "pause.fill"
        case .stop: return "stop.fill"
        case .rewind: return "backward.fill"
        case .fastForward: return "forward.fill"
        case .red, .green, .yellow, .blue: return "circle.fill"
        default: return "number"
        }
    }

    static let digits: [RemoteKey] = [.digit1, .digit2, .digit3, .digit4, .digit5, .digit6, .digit7, .digit8, .digit9]
}

/// Result of sending a command. We distinguish "the TV confirmed it" from "we put
/// it on the wire but the TV doesn't acknowledge this kind of command".
nonisolated enum CommandOutcome: Sendable, Equatable {
    case confirmed
    case sent
    case failed(WebOSError)

    var error: WebOSError? {
        if case .failed(let e) = self { return e }
        return nil
    }
}
