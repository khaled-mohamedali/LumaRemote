import Foundation
import UIKit
import Observation

/// How the remote's centre area navigates the TV.
nonisolated enum NavigationStyle: String, CaseIterable, Sendable, Identifiable {
    /// Arrow ring with a centre OK button, like the physical remote.
    case buttons
    /// Touch-pad: swipe to move, tap for OK.
    case swipe

    var id: String { rawValue }
    var title: String { self == .buttons ? "Arrows" : "Swipe pad" }
    var symbol: String { self == .buttons ? "circle.grid.cross" : "hand.draw" }
}

/// Light/dark appearance. `.system` follows the iPhone's setting.
nonisolated enum AppearanceMode: String, CaseIterable, Sendable, Identifiable {
    case system, light, dark

    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
    var symbol: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }
    var interfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .system: return .unspecified
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// Non-sensitive user preferences, stored in UserDefaults.
@Observable
final class Preferences {
    var hapticsEnabled: Bool { didSet { defaults.set(hapticsEnabled, forKey: "prefs.haptics") } }
    var showExperimentalKeys: Bool { didSet { defaults.set(showExperimentalKeys, forKey: "prefs.experimentalKeys") } }
    var liveTyping: Bool { didSet { defaults.set(liveTyping, forKey: "prefs.liveTyping") } }
    /// App IDs for the two shortcut buttons on the remote ("" = empty slot).
    var shortcutAppIDs: [String] { didSet { defaults.set(shortcutAppIDs, forKey: "prefs.shortcutApps") } }

    var appearance: AppearanceMode { didSet { defaults.set(appearance.rawValue, forKey: "prefs.appearance") } }

    /// Shared by the main remote and the Keyboard screen.
    var navigationStyle: NavigationStyle { didSet { defaults.set(navigationStyle.rawValue, forKey: "prefs.navigationStyle") } }

    static let shortcutSlotCount = 2
    static let defaultShortcuts = ["netflix", "amazon"]

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            "prefs.haptics": true,
            "prefs.experimentalKeys": true,
            "prefs.liveTyping": true,
            "prefs.shortcutApps": Preferences.defaultShortcuts,
        ])
        hapticsEnabled = defaults.bool(forKey: "prefs.haptics")
        showExperimentalKeys = defaults.bool(forKey: "prefs.experimentalKeys")
        liveTyping = defaults.bool(forKey: "prefs.liveTyping")
        appearance = defaults.string(forKey: "prefs.appearance").flatMap(AppearanceMode.init(rawValue:)) ?? .system
        // "keyboard.navStyle" was the Keyboard screen's own setting in 1.1 ("swipe"/"buttons").
        let storedStyle = defaults.string(forKey: "prefs.navigationStyle") ?? defaults.string(forKey: "keyboard.navStyle")
        navigationStyle = storedStyle.flatMap(NavigationStyle.init(rawValue:)) ?? .buttons
        var ids = defaults.stringArray(forKey: "prefs.shortcutApps") ?? Preferences.defaultShortcuts
        while ids.count < Preferences.shortcutSlotCount { ids.append("") }
        shortcutAppIDs = Array(ids.prefix(Preferences.shortcutSlotCount))
    }
}
