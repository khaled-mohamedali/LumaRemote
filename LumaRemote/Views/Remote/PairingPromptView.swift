import SwiftUI

/// First-time pairing. Shows either the code-entry screen (the TV displays a code; no TV
/// remote needed) or the "accept on your TV" screen, and lets you switch between them.
struct PairingPromptView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        switch app.service.phase {
        case .awaitingPin(let request):
            PinEntryView(request: request)
        default:
            AcceptOnTVView()
        }
    }
}

private struct PinEntryView: View {
    @Environment(AppModel.self) private var app
    let request: WebOSService.PinRequest
    @State private var code = ""
    @FocusState private var focused: Bool

    private var digits: String { code.filter(\.isNumber) }
    private var canSubmit: Bool { digits.count >= 4 && !request.verifying }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Image(systemName: "number.square")
                    .font(.system(size: 46))
                    .foregroundStyle(Theme.accent)
                    .padding(.top, 28)
                Text("Enter the code on your TV")
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                Text(subtitle)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 24)

                if let message = request.message {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(Theme.warning)
                        .padding(.horizontal, 24)
                }

                TextField("Code", text: $code)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .font(.system(size: 34, weight: .semibold, design: .monospaced))
                    .multilineTextAlignment(.center)
                    .padding(.vertical, 14)
                    .frame(maxWidth: 280)
                    .card(radius: 16)
                    .focused($focused)
                    .disabled(request.verifying)
                    .onChange(of: code) { _, new in
                        let cleaned = String(new.filter(\.isNumber).prefix(12))
                        if cleaned != new { code = cleaned }
                    }
                    .onSubmit(submit)
                    .accessibilityLabel("Pairing code")

                Button(action: submit) {
                    HStack(spacing: 8) {
                        if request.verifying { ProgressView().tint(.white) }
                        Text(request.verifying ? "Checking…" : "Pair")
                    }
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: 280, minHeight: 50)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(canSubmit || request.verifying ? Theme.accentDeep : Theme.cardRaised))
                    .foregroundStyle(.white)
                }
                .buttonStyle(KeyPressStyle())
                .disabled(!canSubmit)

                VStack(spacing: 12) {
                    Button("Show a new code on the TV") { app.service.restartPairing() }
                    Button("Accept on TV instead (needs TV remote)") { app.service.restartPairing(using: .prompt) }
                    Button("Cancel", role: .cancel) { app.service.disconnect() }
                        .foregroundStyle(Theme.textSecondary)
                }
                .font(.subheadline)
                .disabled(request.verifying)
                .padding(.top, 6)

                Text("The TV issues a pairing key once the code matches. It’s stored only in this iPhone’s Keychain.")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.textSecondary.opacity(0.8))
                    .padding(.horizontal, 28)
                    .padding(.bottom, 24)
            }
            .frame(maxWidth: .infinity)
        }
        .onAppear { focused = true }
        .onChange(of: request) { old, new in
            // A new code was requested after a mismatch: clear the old entry.
            if old.verifying && !new.verifying { code = "" ; focused = true }
        }
    }

    private var subtitle: String {
        let name = app.service.device?.displayName ?? "your TV"
        if request.previousKeyRejected {
            return "\(name) no longer recognises this iPhone, so it’s showing a new pairing code. Type it below."
        }
        return "\(name) is showing a pairing code on screen. Type it below — you don’t need the TV remote."
    }

    private func submit() {
        guard canSubmit else { return }
        app.service.submitPin(digits)
    }
}

private struct AcceptOnTVView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Image(systemName: "tv.badge.wifi")
                    .font(.system(size: 46))
                    .foregroundStyle(Theme.accent)
                    .symbolEffect(.pulse)
                    .padding(.top, 28)
                Text("Accept on your TV")
                    .font(.title2.bold())
                Text(message)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 28)
                if app.service.pinPairingUnavailable {
                    Label("Your TV didn’t offer code pairing, so it’s asking for approval instead.",
                          systemImage: "info.circle")
                        .font(.footnote)
                        .foregroundStyle(Theme.warning)
                        .padding(.horizontal, 28)
                }
                ProgressView().tint(Theme.accent)
                VStack(spacing: 12) {
                    if !app.service.pinPairingUnavailable && app.service.info.supportsPinPairing != false {
                        Button("No TV remote? Use a code instead") { app.service.restartPairing(using: .pin) }
                    }
                    Button("Cancel", role: .cancel) { app.service.disconnect() }
                        .foregroundStyle(Theme.textSecondary)
                }
                .font(.subheadline)
                Text("Luma Remote never bypasses this prompt. The TV issues a pairing key that is stored only in this iPhone’s Keychain.")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.textSecondary.opacity(0.8))
                    .padding(.horizontal, 28)
                    .padding(.bottom, 24)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var message: String {
        if case .awaitingPairing(let previousKeyRejected) = app.service.phase, previousKeyRejected {
            return "Your TV no longer recognises this iPhone (for example after a reset). Use the TV’s own remote to choose “Accept” on the connection request."
        }
        return "A connection request should appear on \(app.service.device?.displayName ?? "your TV"). Use the TV’s own remote to choose “Accept”."
    }
}
