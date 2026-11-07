import Foundation
import Observation

/// Non-sensitive user preferences, stored in UserDefaults.
@Observable
final class Preferences {
    var hapticsEnabled: Bool { didSet { defaults.set(hapticsEnabled, forKey: "prefs.haptics") } }
    var showExperimentalKeys: Bool { didSet { defaults.set(showExperimentalKeys, forKey: "prefs.experimentalKeys") } }
    var liveTyping: Bool { didSet { defaults.set(liveTyping, forKey: "prefs.liveTyping") } }
    /// App IDs for the two shortcut buttons on the remote ("" = empty slot).
    var shortcutAppIDs: [String] { didSet { defaults.set(shortcutAppIDs, forKey: "prefs.shortcutApps") } }

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
        var ids = defaults.stringArray(forKey: "prefs.shortcutApps") ?? Preferences.defaultShortcuts
        while ids.count < Preferences.shortcutSlotCount { ids.append("") }
        shortcutAppIDs = Array(ids.prefix(Preferences.shortcutSlotCount))
    }
}
