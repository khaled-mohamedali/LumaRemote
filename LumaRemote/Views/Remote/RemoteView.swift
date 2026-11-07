import SwiftUI

/// Main remote. Layout follows the LG AKB75675304: power/home/mute on top, the
/// navigation ring in the middle, back/keyboard/input below, and volume/channel
/// rockers either side of the secondary keys.
struct RemoteView: View {
    @Environment(AppModel.self) private var app
    @State private var showDevices = false
    @State private var showKeyboard = false
    @State private var showNumberPad = false
    @State private var showInputs = false
    @State private var showSettings = false

    private var vm: RemoteViewModel { app.remote }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    header
                    DeviceCard(onTap: { showDevices = true })
                    ConnectionBanner()
                    controls
                        .disabled(!vm.isConnected)
                        .opacity(vm.isConnected ? 1 : 0.45)
                        .animation(.easeInOut(duration: 0.25), value: vm.isConnected)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 28)
            }
            .scrollBounceBehavior(.basedOnSize)
            .lumaScreen()
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showDevices) { NavigationStack { DevicesView() } }
            .sheet(isPresented: $showKeyboard) {
                NavigationStack { KeyboardView() }.presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showNumberPad) {
                NumberPadSheet().presentationDetents([.height(470)]).presentationBackground(Theme.background)
            }
            .sheet(isPresented: $showInputs) {
                NavigationStack { InputsList(onPicked: { showInputs = false }) }.presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showSettings) { NavigationStack { MoreView(embedded: true) } }
        }
    }

    private var header: some View {
        HStack {
            Button { showSettings = true } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 20, weight: .medium))
                    .frame(width: 44, height: 44)
            }
            .foregroundStyle(.white)
            .accessibilityLabel("Settings")
            Spacer()
            HStack(spacing: 8) {
                Image(systemName: "tv.fill")
                    .foregroundStyle(Theme.accent)
                Text("Luma Remote").font(.title3.weight(.semibold))
            }
            Spacer()
            StatusPill(phase: vm.phase, text: vm.isConnected ? "Connected" : vm.statusText)
        }
        .padding(.top, 6)
    }

    @ViewBuilder private var controls: some View {
        // Top row: Power · Home · Mute
        HStack {
            if vm.isVisible(.power) {
                CircleKey(symbol: "power", tint: Theme.power, accessibilityLabel: "Power off") { vm.press(.power) }
            } else {
                Color.clear.frame(width: 64, height: 64)
            }
            Spacer()
            CircleKey(symbol: "house.fill", accessibilityLabel: "Home") { vm.press(.home) }
            Spacer()
            CircleKey(symbol: vm.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                      tint: vm.isMuted ? Theme.accent : .white, highlighted: vm.isMuted,
                      accessibilityLabel: vm.isMuted ? "Unmute" : "Mute") { vm.press(.mute) }
        }
        .padding(.horizontal, 12)

        DPadView { vm.press($0) }
            .padding(.vertical, 4)

        // Back · Keyboard · Input
        HStack {
            CircleKey(symbol: "arrow.uturn.backward", accessibilityLabel: "Back") { vm.press(.back) }
            Spacer()
            if vm.capabilities.supports(.insertText) {
                CircleKey(symbol: "keyboard", size: 56, accessibilityLabel: "Keyboard") { showKeyboard = true }
                Spacer()
            }
            if vm.capabilities.supports(.switchInput) {
                CircleKey(accessibilityLabel: "Input source", action: { showInputs = true }) {
                    Text("INPUT").font(.system(size: 13, weight: .bold))
                }
            } else {
                Color.clear.frame(width: 64, height: 64)
            }
        }
        .padding(.horizontal, 12)

        // Volume · secondary keys · Channel
        HStack(alignment: .top) {
            RockerControl(title: volumeTitle, centerSymbol: "speaker.wave.2.fill", centerText: nil,
                          upLabel: "Volume up", downLabel: "Volume down",
                          onUp: { vm.press(.volumeUp) }, onDown: { vm.press(.volumeDown) })
            Spacer()
            VStack(spacing: 10) {
                if vm.isVisible(.settings) {
                    PillKey(title: "Settings", symbol: "gearshape.fill") { vm.press(.settings) }
                }
                if vm.isVisible(.digit1) {
                    PillKey(title: "123", symbol: "circle.grid.3x3.fill") { showNumberPad = true }
                }
                if vm.isVisible(.guide) {
                    PillKey(title: "Guide", symbol: "list.bullet.rectangle", experimental: true) { vm.press(.guide) }
                }
            }
            Spacer()
            if vm.hasChannelControls {
                RockerControl(title: channelTitle, centerSymbol: nil, centerText: "CH",
                              upLabel: "Channel up", downLabel: "Channel down", upRepeats: false,
                              onUp: { vm.press(.channelUp) }, onDown: { vm.press(.channelDown) })
            } else {
                Color.clear.frame(width: 70)
            }
        }
        .padding(.horizontal, 12)

        if vm.hasMediaControls { PlaybackBar() }

        if vm.showsShortcuts { ShortcutRow() }
    }

    private var volumeTitle: String {
        if let v = vm.volume { return "VOL \(v)" }
        return "VOL"
    }

    private var channelTitle: String {
        if let n = app.service.channel?.number { return "CH \(n)" }
        return "CH"
    }
}

struct PlaybackBar: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let vm = app.remote
        HStack(spacing: 0) {
            ForEach([RemoteKey.rewind, .play, .pause, .stop, .fastForward]) { key in
                if vm.isVisible(key) {
                    Button { vm.press(key) } label: {
                        Image(systemName: key.symbol)
                            .font(.system(size: 18, weight: .semibold))
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(KeyPressStyle())
                    .foregroundStyle(.white)
                    .accessibilityLabel(key.title)
                }
            }
        }
        .padding(.horizontal, 6)
        .card(radius: 22)
    }
}

/// Two customizable app shortcuts (Netflix and Prime Video by default, mirroring the
/// AKB75675304's app buttons). Tap to open; long-press or tap an empty slot to choose.
struct ShortcutRow: View {
    @Environment(AppModel.self) private var app
    @State private var editingSlot: EditingSlot?

    struct EditingSlot: Identifiable { let id: Int }

    var body: some View {
        let slots = app.remote.shortcutSlots
        HStack(spacing: 12) {
            ForEach(Array(slots.enumerated()), id: \.offset) { index, point in
                if let point {
                    Button { app.remote.launch(point) } label: {
                        slotLabel {
                            TVImage(urls: point.iconURLs, fallbackSymbol: "play.rectangle.fill")
                                .frame(width: 28, height: 28)
                                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                            Text(point.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                        }
                    }
                    .buttonStyle(KeyPressStyle())
                    .contextMenu {
                        Button { editingSlot = EditingSlot(id: index) } label: {
                            Label("Change App…", systemImage: "arrow.left.arrow.right")
                        }
                        Button(role: .destructive) { app.remote.setShortcut(slot: index, appID: nil) } label: {
                            Label("Remove Shortcut", systemImage: "minus.circle")
                        }
                    }
                    .accessibilityLabel("Open \(point.title)")
                    .accessibilityHint("Touch and hold to change this shortcut")
                } else {
                    Button { editingSlot = EditingSlot(id: index) } label: {
                        slotLabel {
                            Image(systemName: "plus.circle.fill").foregroundStyle(Theme.accent)
                            Text("Choose App").font(.subheadline.weight(.semibold)).lineLimit(1)
                        }
                    }
                    .buttonStyle(KeyPressStyle())
                    .accessibilityLabel("Choose an app for shortcut \(index + 1)")
                }
            }
        }
        .sheet(item: $editingSlot) { slot in
            NavigationStack { AppPickerView(slot: slot.id) }
                .presentationDetents([.medium, .large])
        }
    }

    private func slotLabel<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 10) { content() }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 50)
            .padding(.horizontal, 10)
            .card(radius: 16)
    }
}
