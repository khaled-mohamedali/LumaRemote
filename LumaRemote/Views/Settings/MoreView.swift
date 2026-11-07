import SwiftUI

struct MoreView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    var embedded = false

    var body: some View {
        if embedded {
            list
        } else {
            NavigationStack { list }
        }
    }

    private var list: some View {
        List {
            Section {
                NavigationLink { DevicesView() } label: {
                    row("tv", "Connection", app.service.device.map { "\($0.displayName) · \($0.host)" } ?? "Choose a TV")
                }
                NavigationLink { DeviceInfoView() } label: {
                    row("info.circle", "Device Information", "Model, webOS, capabilities")
                }
                NavigationLink { PairingInfoView() } label: {
                    row("lock.shield", "Pairing", app.service.isPaired ? "Paired · key in Keychain" : "Not paired")
                }
            } header: { Text("TV") }
            .listRowBackground(Theme.card)

            Section {
                NavigationLink { KeyboardView() } label: { row("keyboard", "Keyboard", "Type text on the TV") }
                    .disabled(!app.service.capabilities.supports(.insertText))
                NavigationLink { PowerView() } label: { row("power", "Power & Wake", "Turn off, Wake-on-LAN") }
                Button {
                    app.remote.launch(appID: "com.palm.app.settings", title: "TV Settings")
                } label: {
                    row("gearshape", "Open TV Settings", "Shows the full settings menu on the TV")
                }
                .disabled(!app.service.phase.isConnected)
            } header: { Text("Control") }
            .listRowBackground(Theme.card)

            Section {
                NavigationLink { PreferencesView() } label: { row("slider.horizontal.3", "Preferences", "Shortcuts, haptics, keys, typing") }
                NavigationLink { RemoteMappingView() } label: { row("av.remote", "Physical Remote Mapping", "AKB75675304 key support") }
                NavigationLink { HelpView() } label: { row("questionmark.circle", "Help & Troubleshooting", nil) }
                NavigationLink { AboutView() } label: { row("sparkles", "About Luma Remote", nil) }
            } header: { Text("App") }
            .listRowBackground(Theme.card)
        }
        .listStyle(.insetGrouped)
        .lumaScreen()
        .navigationTitle("More")
        .toolbar {
            if embedded {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
        }
    }

    private func row(_ symbol: String, _ title: String, _ subtitle: String?) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.cardRaised))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).foregroundStyle(.white)
                if let subtitle {
                    Text(subtitle).font(.footnote).foregroundStyle(Theme.textSecondary).lineLimit(1)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

struct PreferencesView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var prefs = app.preferences
        Form {
            Section {
                Toggle("Haptic feedback", isOn: $prefs.hapticsEnabled)
            }
            .listRowBackground(Theme.card)
            Section {
                Toggle("Show experimental keys", isOn: $prefs.showExperimentalKeys)
            } footer: {
                Text("Guide, List and Quick Settings exist on the physical remote but aren’t part of LG’s documented network key set. Some firmware ignores them. They’re marked with an amber dot.")
            }
            .listRowBackground(Theme.card)
            Section {
                ForEach(0..<Preferences.shortcutSlotCount, id: \.self) { slot in
                    NavigationLink {
                        AppPickerView(slot: slot)
                    } label: {
                        LabeledContent("Shortcut \(slot + 1)", value: shortcutName(slot))
                    }
                }
            } header: {
                Text("Remote shortcuts")
            } footer: {
                Text("The two app buttons at the bottom of the remote. You can also touch and hold a shortcut on the remote to change it.")
            }
            .listRowBackground(Theme.card)
            Section {
                Toggle("Live typing", isOn: $prefs.liveTyping)
            } footer: {
                Text("Mirror each keystroke to the TV as you type. Turn off to type first and send with one tap.")
            }
            .listRowBackground(Theme.card)
        }
        .lumaScreen()
        .navigationTitle("Preferences")
    }

    private func shortcutName(_ slot: Int) -> String {
        let ids = app.preferences.shortcutAppIDs
        guard ids.indices.contains(slot), !ids[slot].isEmpty else { return "Empty" }
        let id = ids[slot]
        return app.service.launchPoints.first { $0.id == id }?.title ?? id
    }
}
