import SwiftUI

/// Number pad and the other IR-remote keys that don't fit the main layout.
struct NumberPadSheet: View {
    @Environment(AppModel.self) private var app
    let columns = Array(repeating: GridItem(.flexible(), spacing: 14), count: 3)

    var body: some View {
        let vm = app.remote
        VStack(spacing: 18) {
            Capsule().fill(Theme.textSecondary.opacity(0.4)).frame(width: 36, height: 5).padding(.top, 8)
            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(RemoteKey.digits) { key in digit(key) }
                if vm.isVisible(.list) {
                    small(.list, experimental: true)
                } else {
                    Color.clear.frame(height: 56)
                }
                digit(.digit0)
                small(.dash)
            }
            HStack(spacing: 12) {
                if vm.isVisible(.info) { PillKey(title: "Info", symbol: "info.circle") { vm.press(.info) } }
                if vm.isVisible(.exit) { PillKey(title: "Exit", symbol: "xmark") { vm.press(.exit) } }
                if vm.isVisible(.quickSettings) {
                    PillKey(title: "Quick", symbol: "slider.horizontal.3", experimental: true) { vm.press(.quickSettings) }
                }
            }
            HStack(spacing: 14) {
                ForEach([RemoteKey.red, .green, .yellow, .blue]) { key in
                    Button { vm.press(key) } label: {
                        Capsule().fill(color(key)).frame(height: 14).frame(maxWidth: .infinity, minHeight: 36)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(KeyPressStyle())
                    .accessibilityLabel("\(key.title) key")
                }
            }
            .padding(.horizontal, 6)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .disabled(!vm.isConnected)
    }

    private func digit(_ key: RemoteKey) -> some View {
        Button { app.remote.press(key) } label: {
            Text(key.buttonName ?? "")
                .font(.system(size: 26, weight: .medium, design: .rounded))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.keyGradient))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.stroke))
        }
        .buttonStyle(KeyPressStyle())
        .accessibilityLabel(key.buttonName ?? key.title)
    }

    private func small(_ key: RemoteKey, experimental: Bool = false) -> some View {
        Button { app.remote.press(key) } label: {
            Text(key == .dash ? "–" : key.title.uppercased())
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.card))
                .overlay(alignment: .topTrailing) {
                    if experimental { Circle().fill(Theme.warning).frame(width: 6, height: 6).padding(8) }
                }
        }
        .buttonStyle(KeyPressStyle())
        .accessibilityLabel(key == .dash ? "Dash" : key.title)
    }

    private func color(_ key: RemoteKey) -> Color {
        switch key {
        case .red: return .red
        case .green: return .green
        case .yellow: return .yellow
        default: return .blue
        }
    }
}
