import SwiftUI

struct DeviceCard: View {
    @Environment(AppModel.self) private var app
    let onTap: () -> Void

    var body: some View {
        let device = app.service.device ?? app.deviceStore.selected
        Button(action: onTap) {
            HStack(spacing: 16) {
                Image(systemName: "tv")
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(.white)
                    .frame(width: 52)
                VStack(alignment: .leading, spacing: 3) {
                    Text(device?.displayName ?? "Choose a TV")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        if let model = app.service.info.modelName ?? device?.modelName {
                            Text(model)
                        }
                        if let host = device?.host {
                            Text(host).monospacedDigit()
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                }
                Spacer()
                StatusDot(phase: app.service.phase)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(16)
            .card()
        }
        .buttonStyle(KeyPressStyle())
        .accessibilityHint("Choose or manage TVs")
    }
}

/// Shown when not connected: explains what's happening and offers the next action.
struct ConnectionBanner: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let phase = app.service.phase
        if phase != .connected {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    if phase.isBusy { ProgressView().tint(Theme.accent) }
                    else { Image(systemName: icon(for: phase)).foregroundStyle(color(for: phase)) }
                    Text(title(for: phase)).font(.subheadline.weight(.semibold))
                }
                if let detail = detail(for: phase) {
                    Text(detail).font(.footnote).foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 10) {
                    if case .failed = phase { actionButton("Try Again", "arrow.clockwise") { app.remote.retry() } }
                    if case .idle = phase, app.service.device != nil { actionButton("Connect", "bolt.horizontal") { app.remote.retry() } }
                    if showWake(phase) { actionButton("Wake TV", "power") { app.remote.wake() } }
                    if case .tvOff = phase { actionButton("Reconnect", "arrow.clockwise") { app.remote.retry() } }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .card()
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    private func showWake(_ phase: WebOSService.Phase) -> Bool {
        guard !(app.service.device?.macAddresses.isEmpty ?? true) else { return false }
        switch phase {
        case .tvOff, .failed: return true
        default: return false
        }
    }

    private func actionButton(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 14).padding(.vertical, 9)
                .background(Capsule().fill(Theme.accent.opacity(0.18)))
                .foregroundStyle(Theme.accent)
        }
        .buttonStyle(KeyPressStyle())
    }

    private func icon(for phase: WebOSService.Phase) -> String {
        switch phase {
        case .tvOff: return "moon.zzz.fill"
        case .failed: return "wifi.exclamationmark"
        default: return "tv"
        }
    }

    private func color(for phase: WebOSService.Phase) -> Color {
        if case .failed = phase { return Theme.warning }
        return Theme.textSecondary
    }

    private func title(for phase: WebOSService.Phase) -> String {
        switch phase {
        case .idle: return app.service.device == nil ? "No TV selected" : "Not connected"
        case .connecting(let step): return step
        case .awaitingPairing: return "Waiting for you to accept on the TV"
        case .connected: return "Connected"
        case .reconnecting(let attempt): return "Reconnecting… (attempt \(attempt))"
        case .tvOff: return "Your TV is off or asleep"
        case .failed: return "Can’t connect to your TV"
        }
    }

    private func detail(for phase: WebOSService.Phase) -> String? {
        switch phase {
        case .failed(let error): return error.localizedDescription
        case .tvOff:
            return app.service.device?.macAddresses.isEmpty == false
                ? "Wake TV sends a Wake-on-LAN signal. It only works if “Turn on via Wi-Fi” (Mobile TV On) is enabled on the TV."
                : "Turn the TV on with its remote. To wake it from your phone, connect once while it’s on so Luma Remote can learn its network address, and enable “Turn on via Wi-Fi” on the TV."
        default: return nil
        }
    }
}
