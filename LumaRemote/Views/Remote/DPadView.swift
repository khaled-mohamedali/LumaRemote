import SwiftUI

/// The circular navigation ring with a large central OK key.
struct DPadView: View {
    let onKey: (RemoteKey) -> Void
    let diameter: CGFloat = 270
    let okSize: CGFloat = 104

    var body: some View {
        ZStack {
            Circle()
                .fill(Theme.padGradient)
                .overlay(Circle().strokeBorder(Theme.stroke))
                .shadow(color: .black.opacity(0.55), radius: 22, y: 12)

            arrow(.up).offset(y: -(diameter / 2 - 42))
            arrow(.down).offset(y: diameter / 2 - 42)
            arrow(.left).offset(x: -(diameter / 2 - 42))
            arrow(.right).offset(x: diameter / 2 - 42)

            Button { onKey(.ok) } label: {
                Text("OK")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: okSize, height: okSize)
                    .background(Circle().fill(Theme.keyGradient))
                    .overlay(Circle().strokeBorder(Theme.accent.opacity(0.35), lineWidth: 1.5))
                    .shadow(color: Theme.accentDeep.opacity(0.35), radius: 14)
                    .contentShape(Circle())
            }
            .buttonStyle(KeyPressStyle())
            .accessibilityLabel("OK")
        }
        .frame(width: diameter, height: diameter)
    }

    private func arrow(_ key: RemoteKey) -> some View {
        RepeatingKey(accessibilityLabel: key.title, action: { onKey(key) }) {
            Image(systemName: key.symbol)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 76, height: 76)
        }
    }
}
