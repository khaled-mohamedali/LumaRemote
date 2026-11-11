import SwiftUI

/// Text entry for the TV. Adapts to what's on screen:
/// - a system text field (browser, LG apps): typing goes straight in;
/// - YouTube: type, then "Search YouTube" relaunches it into results;
/// - Netflix, Prime Video…: they ignore typed text, so we show navigation keys for
///   their own on-screen keyboard.
struct KeyboardView: View {
    @Environment(AppModel.self) private var app
    @FocusState private var focused: Bool

    var body: some View {
        @Bindable var vm = app.keyboard
        ScrollView {
            VStack(spacing: 16) {
                switch vm.target {
                case .textField:
                    textFieldMode(vm)
                case .youTube:
                    youTubeMode(vm)
                case .ownKeyboard(let name):
                    ownKeyboardMode(name, vm)
                }
            }
            .padding(20)
        }
        .disabled(!vm.isAvailable)
        .lumaScreen()
        .navigationTitle("Keyboard")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { focused = !isOwnKeyboard(vm.target) }
        .onDisappear { vm.clearLocally() }
    }

    // MARK: Modes

    @ViewBuilder private func textFieldMode(_ model: KeyboardViewModel) -> some View {
        @Bindable var vm = model
        focusHint(vm.tvFieldFocused)
        input($vm.text, prompt: "Type here") { vm.liveTyping ? vm.enter() : vm.sendAll() }
        HStack(spacing: 12) {
            keyButton("Delete", "delete.left") { vm.backspace() }
            if !vm.liveTyping {
                keyButton("Send", "paperplane.fill") { vm.sendAll() }.disabled(vm.text.isEmpty)
            }
            keyButton("Enter", "return") { vm.enter() }
        }
        note(vm.liveTyping
             ? "Live typing is on: each keystroke is sent to the TV."
             : "Type, then tap Send. Turn on Live typing in Preferences to mirror each keystroke.")
    }

    @ViewBuilder private func youTubeMode(_ model: KeyboardViewModel) -> some View {
        @Bindable var vm = model
        banner(symbol: "play.rectangle.fill",
               title: "YouTube is open",
               text: "YouTube uses its own on-screen keyboard, so typed text can’t reach its search box. Type your search here and Luma Remote opens YouTube’s results directly.")
        input($vm.text, prompt: "Search YouTube") { vm.searchYouTube() }
        Button { vm.searchYouTube() } label: {
            Label("Search YouTube", systemImage: "magnifyingglass")
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(vm.text.isEmpty ? Theme.cardRaised : Theme.accentDeep))
                .foregroundStyle(vm.text.isEmpty ? Theme.textSecondary : Color.white)
        }
        .buttonStyle(KeyPressStyle())
        .disabled(vm.text.trimmingCharacters(in: .whitespaces).isEmpty)
        Button("Results didn’t appear? Try another way") { vm.searchYouTube(alternate: true) }
            .font(.footnote)
            .disabled(vm.text.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    @ViewBuilder private func ownKeyboardMode(_ name: String, _ model: KeyboardViewModel) -> some View {
        @Bindable var vm = model
        banner(symbol: "keyboard.badge.ellipsis",
               title: "\(name) uses its own keyboard",
               text: "Typed text can’t reach it. Use the swipe pad to pick letters on its on-screen keyboard, or try a direct search below.")

        @Bindable var prefs = app.preferences
        NavigationStylePicker(style: $prefs.navigationStyle)

        if prefs.navigationStyle == .swipe {
            SwipePad { app.remote.press($0) }
                .frame(height: 260)
        } else {
            DPadView { app.remote.press($0) }
                .scaleEffect(0.8)
                .frame(width: 216, height: 216)
        }
        HStack(spacing: 24) {
            CircleKey(symbol: "arrow.uturn.backward", size: 56, accessibilityLabel: "Back") { app.remote.press(.back) }
            CircleKey(accessibilityLabel: "OK", action: { app.remote.press(.ok) }) {
                Text("OK").font(.system(size: 17, weight: .semibold))
            }
            CircleKey(symbol: "house.fill", size: 56, accessibilityLabel: "Home") { app.remote.press(.home) }
        }

        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text("Try a direct search").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                Text("EXPERIMENTAL")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(Theme.warning.opacity(0.2)))
                    .foregroundStyle(Theme.warning)
            }
            Text("Sends \(name) the same search request LG’s voice assistant uses. If \(name) just reopens instead of showing results, it doesn’t support this.")
                .font(.footnote).foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            input($vm.text, prompt: "Search \(name)") { vm.trySearchLaunch(appName: name) }
            Button { vm.trySearchLaunch(appName: name) } label: {
                Label("Try search in \(name)", systemImage: "magnifyingglass")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .foregroundStyle(Theme.textPrimary)
                    .card(radius: 14)
            }
            .buttonStyle(KeyPressStyle())
            .disabled(vm.text.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(14)
        .card(radius: 16)

        Button("This app shows the LG keyboard? Type anyway") { app.keyboard.typeAnyway() }
            .font(.footnote)
    }

    // MARK: Pieces

    private func isOwnKeyboard(_ target: KeyboardViewModel.Target) -> Bool {
        if case .ownKeyboard = target { return true }
        return false
    }

    private func input(_ text: Binding<String>, prompt: String, onSubmit: @escaping () -> Void) -> some View {
        TextField(prompt, text: text, axis: .vertical)
            .lineLimit(1...4)
            .focused($focused)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.send)
            .onSubmit(onSubmit)
            .padding(16)
            .card(radius: 18)
    }

    private func banner(symbol: String, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).font(.title3).foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                Text(text).font(.footnote).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .card(radius: 16)
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(Theme.textSecondary)
            .multilineTextAlignment(.center)
    }

    @ViewBuilder private func focusHint(_ focus: Bool?) -> some View {
        if !app.keyboard.isAvailable {
            Label("Text input isn’t available. Connect to your TV first.", systemImage: "exclamationmark.triangle")
                .font(.footnote).foregroundStyle(Theme.warning)
        } else if focus == true {
            Label("A text field is active on the TV", systemImage: "checkmark.circle.fill")
                .font(.footnote).foregroundStyle(Theme.success)
        } else if focus == false {
            Label("No text field is active on the TV. Select a search box first — typing won’t appear until you do.",
                  systemImage: "hand.point.up.left")
                .font(.footnote).foregroundStyle(Theme.warning)
                .multilineTextAlignment(.center)
        }
    }

    private func keyButton(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 48)
                .foregroundStyle(Theme.textPrimary)
                .card(radius: 14)
        }
        .buttonStyle(KeyPressStyle())
    }
}
