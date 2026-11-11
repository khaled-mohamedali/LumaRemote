import SwiftUI
import UIKit

/// Colours adapt to light and dark mode. Each token has a light and a dark value;
/// iOS picks the right one from the current appearance (system, or the user's choice
/// in Preferences), including inside sheets.
enum Theme {
    static let background = dynamic(light: 0xF2F2F7, dark: 0x0E0E12)
    static let card = dynamic(light: 0xFFFFFF, dark: 0x1B1B22)
    static let cardRaised = dynamic(light: 0xE8E8EF, dark: 0x25252E)
    static let stroke = dynamic(light: 0x000000, lightAlpha: 0.08, dark: 0xFFFFFF, darkAlpha: 0.06)
    /// Slightly deeper violet in light mode so it keeps contrast on white.
    static let accent = dynamic(light: 0x6B57E8, dark: 0x9D8CFF)
    static let accentDeep = dynamic(light: 0x5A44E0, dark: 0x6B54ED)
    static let textPrimary = dynamic(light: 0x111114, dark: 0xFFFFFF)
    static let textSecondary = dynamic(light: 0x6B6B76, dark: 0x9E9EAB)
    static let power = dynamic(light: 0xE5303D, dark: 0xFF4D5C)
    static let success = dynamic(light: 0x1F9D4D, dark: 0x4DD97A)
    static let warning = dynamic(light: 0xC27400, dark: 0xFFBD47)
    /// Shadows: deep in dark mode, soft in light mode.
    static let shadow = dynamic(light: 0x000000, lightAlpha: 0.12, dark: 0x000000, darkAlpha: 0.45)

    static let keyGradient = LinearGradient(
        colors: [dynamic(light: 0xFFFFFF, dark: 0x2B2B36), dynamic(light: 0xECECF2, dark: 0x1C1C24)],
        startPoint: .top, endPoint: .bottom)

    static let padGradient = LinearGradient(
        colors: [dynamic(light: 0xFFFFFF, dark: 0x292933), dynamic(light: 0xE4E4EC, dark: 0x17171F)],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    nonisolated static func dynamic(light: UInt32, lightAlpha: CGFloat = 1, dark: UInt32, darkAlpha: CGFloat = 1) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(hex: dark, alpha: darkAlpha)
                : UIColor(hex: light, alpha: lightAlpha)
        })
    }
}

extension UIColor {
    nonisolated convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: alpha)
    }
}

/// Applies the user's appearance choice to every window. Done at the UIKit level
/// (rather than SwiftUI's preferredColorScheme) because that reliably switches back to
/// "follow the system" and also restyles sheets that are already open.
enum WindowAppearance {
    static func apply(_ mode: AppearanceMode) {
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows {
                window.overrideUserInterfaceStyle = mode.interfaceStyle
            }
        }
    }
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
