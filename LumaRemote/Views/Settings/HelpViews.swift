import SwiftUI

struct HelpView: View {
    private let topics: [(String, String)] = [
        ("The TV isn’t found automatically",
         "Use “Enter IP address”. Many LG TVs don’t advertise themselves in a way iPhone apps can see. Find the IP on the TV under Settings › All Settings › Network › Wi-Fi Connection › Advanced Wi-Fi Settings. Giving the TV a reserved (static) IP in your router keeps it from changing."),
        ("“Didn’t respond” or “Couldn’t reach”",
         "Check the TV is on and on the same Wi-Fi as your iPhone (guest networks often isolate devices). On the TV, make sure Settings › General › Mobile TV On / LG Connect Apps is enabled."),
        ("Local Network permission",
         "iOS asks once whether Luma Remote may find devices on your network. If you declined, enable it in iPhone Settings › Privacy & Security › Local Network › Luma Remote. Without it no connection is possible."),
        ("No TV remote to accept the connection",
         "Use code pairing (the default): the TV shows a code on screen and you type it on your iPhone. You can switch any TV between “Code on TV” and “Accept on TV” in its details, or from the pairing screen."),
        ("No code or prompt appears on the TV",
         "Make sure the TV is showing a normal picture (not in standby), then tap Try Again. If your TV doesn’t offer code pairing, Luma Remote tells you and uses the Accept prompt instead."),
        ("The code didn’t work",
         "Each wrong code ends that pairing attempt, and the TV shows a new code. Type the new one. After three wrong codes, tap Try Again to start over."),
        ("Pairing was declined",
         "Tap Try Again and choose Accept on the TV. If you previously blocked the device on the TV, remove it from the TV’s connected-devices list first."),
        ("Asked to pair again",
         "The TV forgets paired apps after a factory reset or some firmware updates. Accept the prompt again; the new key replaces the old one."),
        ("Certificate changed",
         "Firmware updates can change the TV’s security certificate. If you just updated the TV, open the TV’s details in Devices and tap Reset certificate trust."),
        ("Typing doesn’t show up in YouTube, Netflix, Prime Video…",
         "Most third-party apps draw their own on-screen keyboard instead of LG’s, so text typed from a phone can’t reach them. With YouTube open, the Keyboard screen becomes “Search YouTube” and opens the results directly. For Netflix and similar apps it shows arrow keys to pick letters on the app’s own keyboard."),
        ("A button does nothing",
         "Some keys are delivered as button events that the TV doesn’t acknowledge. Keys marked with an amber dot are experimental and may be ignored by your firmware. Features the TV reports as unsupported are hidden automatically."),
        ("Turning the TV on",
         "See More › Power & Wake. Waking over the network needs “Turn on via Wi-Fi” enabled on the TV and isn’t guaranteed on iPhone."),
    ]

    var body: some View {
        List {
            ForEach(topics, id: \.0) { topic in
                DisclosureGroup {
                    Text(topic.1).font(.subheadline).foregroundStyle(Theme.textSecondary).padding(.vertical, 4)
                } label: {
                    Text(topic.0).foregroundStyle(.white)
                }
                .listRowBackground(Theme.card)
            }
        }
        .listStyle(.insetGrouped)
        .lumaScreen()
        .navigationTitle("Help")
    }
}

/// How each key on the LG AKB75675304 maps to the network API.
struct RemoteMappingView: View {
    private enum Support { case confirmed, button, experimental, unavailable }

    private let rows: [(String, Support, String)] = [
        ("Power", .confirmed, "Off only via ssap://system/turnOff. On needs Wake-on-LAN."),
        ("Number pad 0–9, –", .button, "Button events on the pointer socket."),
        ("Volume + / –", .confirmed, "ssap://audio/volumeUp / volumeDown"),
        ("Channel + / –", .confirmed, "ssap://tv/channelUp / channelDown"),
        ("Mute", .confirmed, "ssap://audio/setMute"),
        ("Home", .button, "HOME button event"),
        ("Settings (gear)", .button, "MENU button event; “Open TV Settings” in More launches the full menu (confirmed)."),
        ("Arrows / OK", .button, "UP/DOWN/LEFT/RIGHT/ENTER button events"),
        ("Back / Exit", .button, "BACK / EXIT button events"),
        ("Input", .confirmed, "Input list from the TV; ssap://tv/switchInput"),
        ("Guide", .experimental, "GUIDE button event — undocumented"),
        ("List", .experimental, "LIST button event — undocumented"),
        ("Playback (▶︎ ❚❚ ■ ◀◀ ▶▶)", .confirmed, "ssap://media.controls/*, falls back to button events"),
        ("Colour keys", .button, "RED/GREEN/YELLOW/BLUE button events"),
        ("Netflix / Prime Video", .confirmed, "Shown only if installed; launched via ssap://system.launcher/launch"),
        ("Quick Access (hold a number)", .unavailable, "Stored on the TV and triggered only by the IR remote. Use the Apps tab instead."),
        ("Q.Settings", .experimental, "QMENU button event — undocumented"),
        ("Magic-remote pointer", .unavailable, "Your AKB75675304 is a standard IR remote; pointer control isn’t part of this app."),
    ]

    var body: some View {
        List {
            Section {
                ForEach(rows, id: \.0) { row in
                    HStack(alignment: .top, spacing: 12) {
                        badge(row.1)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(row.0).foregroundStyle(.white)
                            Text(row.2).font(.footnote).foregroundStyle(Theme.textSecondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            } footer: {
                Text("Confirmed: the TV replies to say it worked. Sent: delivered as a button event, which the TV doesn’t acknowledge. Experimental: on the IR remote but not documented for the network API. Not available: no network equivalent exists.")
            }
            .listRowBackground(Theme.card)
        }
        .listStyle(.insetGrouped)
        .lumaScreen()
        .navigationTitle("LG AKB75675304")
    }

    @ViewBuilder private func badge(_ s: Support) -> some View {
        switch s {
        case .confirmed: Image(systemName: "checkmark.seal.fill").foregroundStyle(Theme.success)
        case .button: Image(systemName: "paperplane.fill").foregroundStyle(Theme.accent)
        case .experimental: Image(systemName: "flask.fill").foregroundStyle(Theme.warning)
        case .unavailable: Image(systemName: "nosign").foregroundStyle(Theme.textSecondary)
        }
    }
}

struct AboutView: View {
    var body: some View {
        List {
            Section {
                VStack(spacing: 10) {
                    Image(systemName: "av.remote.fill").font(.system(size: 44)).foregroundStyle(Theme.accent)
                    Text("Luma Remote").font(.title2.bold())
                    Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")")
                        .font(.footnote).foregroundStyle(Theme.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            .listRowBackground(Theme.card)
            Section {
                Text("No ads. No subscriptions. No analytics or tracking. No accounts.")
                Text("Luma Remote talks only to your TV on your local network, using LG’s webOS Second Screen protocol (SSAP).")
                Text("Built with SwiftUI and Apple frameworks only — no third-party code.")
            }
            .font(.subheadline)
            .listRowBackground(Theme.card)
            Section {
                Text("LG and webOS are trademarks of LG Electronics. Luma Remote is an independent personal project and is not affiliated with LG.")
                    .font(.footnote).foregroundStyle(Theme.textSecondary)
            }
            .listRowBackground(Theme.card)
        }
        .listStyle(.insetGrouped)
        .lumaScreen()
        .navigationTitle("About")
    }
}
