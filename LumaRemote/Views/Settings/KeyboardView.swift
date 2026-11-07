import SwiftUI

struct KeyboardView: View {
    @Environment(AppModel.self) private var app
    @FocusState private var focused: Bool

    var body: some View {
        @Bindable var vm = app.keyboard
        VStack(spacing: 16) {
            focusHint(vm.tvFieldFocused)

            TextField("Type here", text: $vm.text, axis: .vertical)
                .lineLimit(1...4)
                .focused($focused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.send)
                .onSubmit { vm.liveTyping ? vm.enter() : vm.sendAll() }
                .padding(16)
                .card(radius: 18)

            HStack(spacing: 12) {
                keyButton("Delete", "delete.left") { vm.backspace() }
                if !vm.liveTyping {
                    keyButton("Send", "paperplane.fill") { vm.sendAll() }.disabled(vm.text.isEmpty)
                }
                keyButton("Enter", "return") { vm.enter() }
            }

            Text(vm.liveTyping
                 ? "Live typing is on: each keystroke is sent to the TV."
                 : "Type, then tap Send. Turn on Live typing in Preferences to mirror each keystroke.")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(20)
        .disabled(!vm.isAvailable)
        .lumaScreen()
        .navigationTitle("Keyboard")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { focused = true }
        .onDisappear { vm.clearLocally() }
    }

    @ViewBuilder private func focusHint(_ focus: Bool?) -> some View {
        if !app.keyboard.isAvailable {
            Label("Text input isn’t available. Connect to your TV first.", systemImage: "exclamationmark.triangle")
                .font(.footnote).foregroundStyle(Theme.warning)
        } else if focus == true {
            Label("A text field is active on the TV", systemImage: "checkmark.circle.fill")
                .font(.footnote).foregroundStyle(Theme.success)
        } else if focus == false {
            Label("Select a search box or text field on the TV first", systemImage: "hand.point.up.left")
                .font(.footnote).foregroundStyle(Theme.textSecondary)
        }
    }

    private func keyButton(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 48)
                .foregroundStyle(.white)
                .card(radius: 14)
        }
        .buttonStyle(KeyPressStyle())
    }
}
