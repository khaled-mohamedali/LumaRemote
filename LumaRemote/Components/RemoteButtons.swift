import SwiftUI

/// Press feedback shared by all remote keys.
struct KeyPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.93 : 1)
            .brightness(configuration.isPressed ? 0.06 : 0)
            .animation(.spring(response: 0.22, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Round key (Power / Home / Mute / Back / …). 64pt keeps one-handed use comfortable.
struct CircleKey<Label: View>: View {
    var size: CGFloat = 64
    var tint: Color = .white
    var highlighted = false
    var accessibilityLabel: String
    let action: () -> Void
    @ViewBuilder var label: () -> Label

    var body: some View {
        Button(action: action) {
            label()
                .foregroundStyle(tint)
                .frame(width: size, height: size)
                .background(Circle().fill(Theme.keyGradient))
                .overlay(Circle().strokeBorder(highlighted ? Theme.accent.opacity(0.8) : Theme.stroke, lineWidth: highlighted ? 1.5 : 1))
                .shadow(color: .black.opacity(0.45), radius: 10, y: 6)
                .contentShape(Circle())
        }
        .buttonStyle(KeyPressStyle())
        .accessibilityLabel(accessibilityLabel)
    }
}

extension CircleKey where Label == SymbolLabel {
    init(symbol: String, size: CGFloat = 64, tint: Color = .white, highlighted: Bool = false,
         accessibilityLabel: String, action: @escaping () -> Void) {
        self.size = size
        self.tint = tint
        self.highlighted = highlighted
        self.accessibilityLabel = accessibilityLabel
        self.action = action
        self.label = { SymbolLabel(symbol: symbol, size: size) }
    }
}

struct SymbolLabel: View {
    let symbol: String
    let size: CGFloat
    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.34, weight: .semibold))
    }
}

/// A view that fires `action` on touch-down and repeats while held (for volume and
/// the D-pad arrows), like holding a key on the physical remote.
struct RepeatingKey<Label: View>: View {
    var accessibilityLabel: String
    var repeats = true
    let action: () -> Void
    @ViewBuilder var label: () -> Label

    @State private var isPressed = false
    @State private var repeatTask: Task<Void, Never>?

    var body: some View {
        label()
            .scaleEffect(isPressed ? 0.92 : 1)
            .brightness(isPressed ? 0.08 : 0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isPressed)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !isPressed else { return }
                        isPressed = true
                        action()
                        guard repeats else { return }
                        repeatTask = Task {
                            try? await Task.sleep(for: .milliseconds(450))
                            while !Task.isCancelled {
                                action()
                                try? await Task.sleep(for: .milliseconds(160))
                            }
                        }
                    }
                    .onEnded { _ in
                        isPressed = false
                        repeatTask?.cancel()
                        repeatTask = nil
                    }
            )
            .onDisappear { repeatTask?.cancel(); repeatTask = nil }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { action() }
    }
}

/// Vertical +/– rocker for volume and channel, modeled on the physical remote.
struct RockerControl: View {
    let title: String
    let centerSymbol: String?
    let centerText: String?
    let upLabel: String
    let downLabel: String
    var upRepeats = true
    let onUp: () -> Void
    let onDown: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            VStack(spacing: 0) {
                RepeatingKey(accessibilityLabel: upLabel, repeats: upRepeats, action: onUp) {
                    Image(systemName: "plus")
                        .font(.system(size: 20, weight: .semibold))
                        .frame(width: 70, height: 58)
                }
                Group {
                    if let centerSymbol {
                        Image(systemName: centerSymbol).font(.system(size: 17, weight: .medium))
                    } else if let centerText {
                        Text(centerText).font(.system(size: 15, weight: .semibold))
                    }
                }
                .foregroundStyle(Theme.textSecondary)
                .frame(height: 26)
                .accessibilityHidden(true)
                RepeatingKey(accessibilityLabel: downLabel, repeats: upRepeats, action: onDown) {
                    Image(systemName: "minus")
                        .font(.system(size: 20, weight: .semibold))
                        .frame(width: 70, height: 58)
                }
            }
            .foregroundStyle(.white)
            .background(Capsule().fill(Theme.keyGradient))
            .overlay(Capsule().strokeBorder(Theme.stroke))
            .shadow(color: .black.opacity(0.45), radius: 10, y: 6)

            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
        }
    }
}

/// Small pill key used for secondary functions (Settings, 123, Guide, Info…).
struct PillKey: View {
    let title: String
    let symbol: String
    var experimental = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 16, weight: .semibold))
                Text(title).font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(width: 70, height: 54)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.keyGradient))
            .overlay(alignment: .topTrailing) {
                if experimental {
                    Circle().fill(Theme.warning).frame(width: 6, height: 6).padding(7)
                        .accessibilityHidden(true)
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.stroke))
        }
        .buttonStyle(KeyPressStyle())
        .accessibilityLabel(experimental ? "\(title), experimental" : title)
    }
}
