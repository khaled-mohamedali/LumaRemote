import SwiftUI
import UIKit

enum Theme {
    static let background = Color(red: 0.055, green: 0.055, blue: 0.071)      // #0E0E12
    static let card = Color(red: 0.105, green: 0.105, blue: 0.133)            // #1B1B22
    static let cardRaised = Color(red: 0.145, green: 0.145, blue: 0.180)      // #25252E
    static let stroke = Color.white.opacity(0.06)
    static let accent = Color(red: 0.616, green: 0.549, blue: 1.0)            // #9D8CFF
    static let accentDeep = Color(red: 0.42, green: 0.33, blue: 0.93)
    static let textPrimary = Color.white
    static let textSecondary = Color(red: 0.62, green: 0.62, blue: 0.67)
    static let power = Color(red: 1.0, green: 0.30, blue: 0.36)
    static let success = Color(red: 0.30, green: 0.85, blue: 0.48)
    static let warning = Color(red: 1.0, green: 0.74, blue: 0.28)

    static let keyGradient = LinearGradient(
        colors: [Color(red: 0.17, green: 0.17, blue: 0.21), Color(red: 0.11, green: 0.11, blue: 0.14)],
        startPoint: .top, endPoint: .bottom)

    static let padGradient = LinearGradient(
        colors: [Color(red: 0.16, green: 0.16, blue: 0.20), Color(red: 0.09, green: 0.09, blue: 0.12)],
        startPoint: .topLeading, endPoint: .bottomTrailing)
}

enum Haptics {
    static func tap(enabled: Bool, strong: Bool = false) {
        guard enabled else { return }
        let generator = UIImpactFeedbackGenerator(style: strong ? .medium : .light)
        generator.impactOccurred()
    }

    static func error(enabled: Bool) {
        guard enabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }

    static func success(enabled: Bool) {
        guard enabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}

/// Rounded card background used throughout.
struct CardBackground: ViewModifier {
    var radius: CGFloat = 20
    func body(content: Content) -> some View {
        content
            .background(Theme.card, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Theme.stroke))
    }
}

extension View {
    func card(radius: CGFloat = 20) -> some View { modifier(CardBackground(radius: radius)) }

    /// Standard dark screen background.
    func lumaScreen() -> some View {
        background(Theme.background.ignoresSafeArea())
            .scrollContentBackground(.hidden)
    }
}
