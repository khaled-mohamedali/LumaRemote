import SwiftUI

struct PairingPromptView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
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
            ProgressView().tint(Theme.accent)
            Text("Luma Remote never bypasses this prompt. The TV issues a pairing key that is stored only in this iPhone’s Keychain.")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.textSecondary.opacity(0.8))
                .padding(.horizontal, 28)
            Button("Cancel", role: .cancel) { app.service.disconnect() }
                .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity)
    }

    private var message: String {
        if case .awaitingPairing(let previousKeyRejected) = app.service.phase, previousKeyRejected {
            return "Your TV no longer recognises this iPhone (for example after a reset). Use the TV’s own remote to choose “Accept” on the connection request."
        }
        return "A connection request should appear on \(app.service.device?.displayName ?? "your TV"). Use the TV’s own remote to choose “Accept”."
    }
}
