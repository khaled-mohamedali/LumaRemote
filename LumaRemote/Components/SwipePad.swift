import SwiftUI

/// Touch-pad style navigation for apps that draw their own on-screen keyboard
/// (Netflix, Prime Video…). Every `step` points of finger travel sends one arrow key,
/// so a short swipe moves one key and a long drag keeps moving; a tap sends OK.
/// Only the dominant axis counts, so slightly diagonal swipes don't wander.
struct SwipePad: View {
    let onKey: (RemoteKey) -> Void
    /// Finger travel per key press. ~34pt feels like one key per flick.
    var step: CGFloat = 34

    @State private var anchor: CGSize?
    @State private var movedThisTouch = false
    @State private var flashed: RemoteKey?
    @State private var flashTask: Task<Void, Never>?

    var body: some View {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .fill(Theme.padGradient)
            .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(Theme.stroke))
            .overlay {
                ZStack {
                    if let flashed {
                        Image(systemName: flashed == .ok ? "circle.fill" : flashed.symbol)
                            .font(.system(size: 44, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                            .transition(.scale.combined(with: .opacity))
                    } else {
                        VStack(spacing: 6) {
                            Image(systemName: "hand.draw")
                                .font(.system(size: 28))
                            Text("Swipe to move · Tap to select")
                                .font(.footnote.weight(.medium))
                        }
                        .foregroundStyle(Theme.textSecondary)
                    }
                }
                .animation(.easeOut(duration: 0.15), value: flashed)
                .allowsHitTesting(false)
            }
            .shadow(color: .black.opacity(0.45), radius: 16, y: 8)
            .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged(handleChange)
                    .onEnded(handleEnd)
            )
            .accessibilityElement()
            .accessibilityLabel("Swipe pad")
            .accessibilityHint("Swipe to move on the TV, tap to select")
            .accessibilityAction(named: "Up") { send(.up) }
            .accessibilityAction(named: "Down") { send(.down) }
            .accessibilityAction(named: "Left") { send(.left) }
            .accessibilityAction(named: "Right") { send(.right) }
            .accessibilityAction { send(.ok) }
            .onDisappear { flashTask?.cancel() }
    }

    private func handleChange(_ value: DragGesture.Value) {
        var origin = anchor ?? .zero
        var dx = value.translation.width - origin.width
        var dy = value.translation.height - origin.height
        // A fast swipe can cover several steps between two touch events.
        while max(abs(dx), abs(dy)) >= step {
            if abs(dx) >= abs(dy) {
                send(dx > 0 ? .right : .left)
                origin.width += dx > 0 ? step : -step
                origin.height = value.translation.height    // ignore drift on the other axis
            } else {
                send(dy > 0 ? .down : .up)
                origin.height += dy > 0 ? step : -step
                origin.width = value.translation.width
            }
            movedThisTouch = true
            dx = value.translation.width - origin.width
            dy = value.translation.height - origin.height
        }
        anchor = origin
    }

    private func handleEnd(_ value: DragGesture.Value) {
        let distance = hypot(value.translation.width, value.translation.height)
        if !movedThisTouch && distance < 12 { send(.ok) }
        anchor = nil
        movedThisTouch = false
    }

    private func send(_ key: RemoteKey) {
        onKey(key)
        flashed = key
        flashTask?.cancel()
        flashTask = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            flashed = nil
        }
    }
}
