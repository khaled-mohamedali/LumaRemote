import Foundation
import Observation

/// Non-sensitive user preferences, stored in UserDefaults.
@Observable
final class Preferences {
    var hapticsEnabled: Bool { didSet { defaults.set(hapticsEnabled, forKey: "prefs.haptics") } }
    var showExperimentalKeys: Bool { didSet { defaults.set(showExperimentalKeys, forKey: "prefs.experimentalKeys") } }
    var liveTyping: Bool { didSet { defaults.set(liveTyping, forKey: "prefs.liveTyping") } }

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            "prefs.haptics": true,
            "prefs.experimentalKeys": true,
            "prefs.liveTyping": true,
        ])
        hapticsEnabled = defaults.bool(forKey: "prefs.haptics")
        showExperimentalKeys = defaults.bool(forKey: "prefs.experimentalKeys")
        liveTyping = defaults.bool(forKey: "prefs.liveTyping")
    }
}
