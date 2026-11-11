import SwiftUI

struct InputsView: View {
    var body: some View {
        NavigationStack {
            InputsList(onPicked: nil)
        }
    }
}

/// Inputs exactly as the TV reports them (`tv/getExternalInputList`). The TV tuner is
/// shown only if the Live TV app exists on this TV.
struct InputsList: View {
    @Environment(AppModel.self) private var app
    let onPicked: (() -> Void)?

    let liveTVAppID = "com.webos.app.livetv"

    var body: some View {
        content
            .navigationTitle("Inputs")
            .lumaScreen()
            .toolbarBackground(Theme.background, for: .navigationBar)
    }

    @ViewBuilder private var content: some View {
        let service = app.service
        if !service.phase.isConnected {
            ContentUnavailableView("Not Connected", systemImage: "tv.slash",
                                   description: Text("Connect to your TV to see its inputs."))
        } else if !service.capabilities.supports(.externalInputs) {
            ContentUnavailableView("Inputs Unavailable", systemImage: "rectangle.connected.to.line.below",
                                   description: Text("This TV’s firmware doesn’t share its input list over the network."))
        } else if !service.inputsLoaded {
            ProgressView("Loading inputs…").tint(Theme.accent)
        } else {
            List {
                Section {
                    if let live = service.launchPoints.first(where: { $0.id == liveTVAppID }) {
                        row(title: "TV", subtitle: "Antenna / cable tuner", symbol: "antenna.radiowaves.left.and.right",
                            iconURL: nil, connected: true, current: service.foregroundAppID == live.id) {
                            app.remote.launch(appID: live.id, title: "Live TV")
                            onPicked?()
                        }
                    }
                    ForEach(service.inputs) { input in
                        row(title: input.label, subtitle: input.connected ? "Device connected" : "Nothing detected",
                            symbol: input.symbol, iconURL: input.iconURL, connected: input.connected,
                            current: input.appId != nil && service.foregroundAppID == input.appId) {
                            app.remote.switchInput(input)
                            onPicked?()
                        }
                    }
                } footer: {
                    Text("Only inputs reported by your TV are listed.")
                }
                .listRowBackground(Theme.card)
            }
            .listStyle(.insetGrouped)
        }
    }

    private func row(title: String, subtitle: String, symbol: String, iconURL: URL?, connected: Bool,
                     current: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 20))
                    .foregroundStyle(current ? Theme.accent : Theme.textPrimary)
                    .frame(width: 40, height: 40)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.cardRaised))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body.weight(.medium)).foregroundStyle(Theme.textPrimary)
                    Text(subtitle).font(.footnote).foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                if current {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent)
                } else if connected {
                    Circle().fill(Theme.success).frame(width: 8, height: 8)
                }
            }
            .padding(.vertical, 4)
        }
        .accessibilityLabel("\(title), \(subtitle)\(current ? ", current input" : "")")
    }
}
