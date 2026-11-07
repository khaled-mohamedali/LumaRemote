import SwiftUI

struct StatusDot: View {
    let phase: WebOSService.Phase
    @State private var pulse = false

    var color: Color {
        switch phase {
        case .connected: return Theme.success
        case .connecting, .awaitingPairing, .reconnecting: return Theme.warning
        case .tvOff, .idle: return Theme.textSecondary
        case .failed: return Theme.power
        }
    }

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .overlay(Circle().stroke(color.opacity(0.5), lineWidth: 4).scaleEffect(pulse ? 1.9 : 1).opacity(pulse ? 0 : 1))
            .onAppear { pulse = phase.isBusy }
            .onChange(of: phase) { _, p in pulse = false; if p.isBusy { withAnimation(.easeOut(duration: 1.2).repeatForever(autoreverses: false)) { pulse = true } } }
            .accessibilityHidden(true)
    }
}

struct StatusPill: View {
    let phase: WebOSService.Phase
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            StatusDot(phase: phase)
            Text(text)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(phase.isConnected ? Theme.success : Theme.textSecondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(Theme.card))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Status: \(text)")
    }
}

struct ToastView: View {
    let toast: RemoteViewModel.Toast

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: toast.style == .error ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(toast.style == .error ? Theme.warning : Theme.accent)
            Text(toast.message)
                .font(.subheadline)
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.stroke))
        .shadow(color: .black.opacity(0.4), radius: 16, y: 8)
        .padding(.horizontal, 16)
        .accessibilityElement(children: .combine)
    }
}

/// App icon / input icon served by the TV, with a graceful placeholder.
struct TVImage: View {
    let urls: [URL]
    let fallbackSymbol: String

    init(urls: [URL], fallbackSymbol: String) {
        self.urls = urls
        self.fallbackSymbol = fallbackSymbol
    }

    init(url: URL?, fallbackSymbol: String) {
        self.init(urls: url.map { [$0] } ?? [], fallbackSymbol: fallbackSymbol)
    }

    @Environment(AppModel.self) private var app
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                Image(systemName: fallbackSymbol)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .task(id: urls) {
            guard !urls.isEmpty else { return }
            image = await app.service.icon(for: urls)
        }
    }
}

struct SectionHeader: View {
    let title: String
    var body: some View {
        Text(title.uppercased())
            .font(.caption.weight(.semibold))
            .foregroundStyle(Theme.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
