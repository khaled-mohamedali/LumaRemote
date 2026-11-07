import SwiftUI

/// Manual IP entry — the path that's guaranteed to work even when discovery doesn't.
struct AddDeviceView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let onSaved: () -> Void
    @FocusState private var hostFocused: Bool

    var body: some View {
        @Bindable var vm = app.devices
        Form {
            Section {
                TextField("192.168.1.54", text: $vm.manualHost)
                    .keyboardType(.decimalPad)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.body.monospacedDigit())
                    .focused($hostFocused)
                TextField("Name (optional)", text: $vm.manualName)
            } header: {
                Text("TV address")
            } footer: {
                if let message = vm.hostValidationMessage {
                    Text(message).foregroundStyle(Theme.warning)
                } else {
                    Text("On the TV: Settings › All Settings › Network › Wi-Fi Connection › Advanced Wi-Fi Settings.")
                }
            }
            .listRowBackground(Theme.card)

            Section {
                Picker("Connection", selection: $vm.manualTransport) {
                    ForEach(TransportPreference.allCases) { Text($0.title).tag($0) }
                }
                TextField("Port (default 3001 / 3000)", text: $vm.manualPort)
                    .keyboardType(.numberPad)
            } header: {
                Text("Advanced")
            } footer: {
                if vm.portIsInvalid {
                    Text("Ports range from 1 to 65535.").foregroundStyle(Theme.warning)
                } else {
                    Text("Leave on Automatic. Newer LG firmware uses a secure connection on port 3001; older firmware uses port 3000. Luma Remote tries both and remembers what works.")
                }
            }
            .listRowBackground(Theme.card)

            Section {
                Button {
                    hostFocused = false
                    vm.testConnection()
                } label: {
                    HStack {
                        Label("Test connection", systemImage: "antenna.radiowaves.left.and.right")
                        Spacer()
                        if vm.testState == .testing { ProgressView() }
                    }
                }
                .disabled(!vm.canSubmitManual || vm.testState == .testing)

                testResult(vm.testState)
            }
            .listRowBackground(Theme.card)

            Section {
                Button {
                    vm.saveManualAndConnect()
                    onSaved()
                } label: {
                    Text("Save & Pair").frame(maxWidth: .infinity).font(.body.weight(.semibold))
                }
                .disabled(!vm.canSubmitManual)
            } footer: {
                Text("Your TV will ask you to accept the connection. Use the TV’s own remote to choose Accept.")
            }
            .listRowBackground(Theme.accentDeep.opacity(vm.canSubmitManual ? 0.9 : 0.3))
            .foregroundStyle(.white)
        }
        .lumaScreen()
        .navigationTitle("Add TV")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { vm.resetForm(); dismiss() }
            }
        }
        .onAppear { hostFocused = vm.manualHost.isEmpty }
    }

    @ViewBuilder private func testResult(_ state: DevicesViewModel.TestState) -> some View {
        switch state {
        case .idle, .testing:
            EmptyView()
        case .success(let result):
            VStack(alignment: .leading, spacing: 4) {
                Label("LG webOS TV found", systemImage: "checkmark.circle.fill").foregroundStyle(Theme.success)
                Group {
                    if let model = result.modelName { Text("Model: \(model)") }
                    if let version = result.webOSVersion { Text("webOS: \(version)") }
                    Text("Connection: \(result.endpoint.label)")
                }
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
            }
        case .failure(let error):
            Label(error.localizedDescription, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.warning)
                .font(.footnote)
        }
    }
}
