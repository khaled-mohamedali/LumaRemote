import SwiftUI

/// Per-TV settings: rename, address/port/transport, MAC for Wake-on-LAN, pairing and
/// certificate trust, removal.
struct DeviceDetailView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let deviceID: UUID

    @State private var draft: SavedDevice?
    @State private var portText = ""
    @State private var macText = ""
    @State private var confirmRemove = false
    @State private var confirmForget = false

    var body: some View {
        Form {
            if let binding = Binding($draft) {
                Section("Name") {
                    TextField("Living room TV", text: binding.name)
                }
                .listRowBackground(Theme.card)

                Section {
                    TextField("IP address", text: binding.host)
                        .keyboardType(.decimalPad)
                        .font(.body.monospacedDigit())
                    Picker("Connection", selection: binding.transport) {
                        ForEach(TransportPreference.allCases) { Text($0.title).tag($0) }
                    }
                    TextField("Custom port (optional)", text: $portText)
                        .keyboardType(.numberPad)
                    if let endpoint = binding.wrappedValue.lastWorkingEndpoint {
                        LabeledContent("Last working", value: endpoint.label)
                    }
                } header: {
                    Text("Connection")
                } footer: {
                    if IPv4(binding.wrappedValue.host) == nil {
                        Text("Enter a valid IPv4 address.").foregroundStyle(Theme.warning)
                    }
                }
                .listRowBackground(Theme.card)

                Section {
                    TextField("AA:BB:CC:DD:EE:FF", text: $macText)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .font(.body.monospaced())
                } header: {
                    Text("Wake-on-LAN MAC address")
                } footer: {
                    Text("Learned automatically from the TV after pairing. Separate several with commas (Wi-Fi and Ethernet).")
                }
                .listRowBackground(Theme.card)

                Section {
                    LabeledContent("Pairing key", value: app.devices.isPaired(binding.wrappedValue) ? "Stored in Keychain" : "Not paired")
                    if let fp = binding.wrappedValue.certificateFingerprint {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Trusted certificate (SHA-256)")
                            Text(fp).font(.caption2.monospaced()).foregroundStyle(Theme.textSecondary)
                        }
                        Button("Reset certificate trust") {
                            app.devices.resetTrust(binding.wrappedValue)
                            draft?.certificateFingerprint = nil
                        }
                    }
                    Button("Forget pairing", role: .destructive) { confirmForget = true }
                        .disabled(!app.devices.isPaired(binding.wrappedValue))
                } header: {
                    Text("Security")
                }
                .listRowBackground(Theme.card)

                Section {
                    Button("Remove TV", role: .destructive) { confirmRemove = true }
                }
                .listRowBackground(Theme.card)
            }
        }
        .lumaScreen()
        .navigationTitle(draft?.displayName ?? "TV")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }.disabled(!isValid)
            }
        }
        .onAppear(perform: load)
        .confirmationDialog("Remove this TV?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                if let draft { app.devices.remove(draft) }
                dismiss()
            }
        } message: {
            Text("The pairing key will be deleted from this iPhone.")
        }
        .confirmationDialog("Forget pairing?", isPresented: $confirmForget, titleVisibility: .visible) {
            Button("Forget", role: .destructive) { if let draft { app.devices.forgetPairing(draft) } }
        } message: {
            Text("You’ll need to accept a new connection request on the TV next time.")
        }
    }

    private var isValid: Bool {
        guard let draft, IPv4(draft.host) != nil else { return false }
        let p = portText.trimmingCharacters(in: .whitespaces)
        return p.isEmpty || (Int(p).map { (1...65535).contains($0) } ?? false)
    }

    private func load() {
        guard draft == nil, let device = app.deviceStore.device(deviceID) else { return }
        draft = device
        portText = device.customPort.map { String($0) } ?? ""
        macText = device.macAddresses.joined(separator: ", ")
    }

    private func save() {
        guard var device = draft, let original = app.deviceStore.device(deviceID) else { return }
        device.host = device.host.trimmingCharacters(in: .whitespaces)
        device.customPort = Int(portText.trimmingCharacters(in: .whitespaces))
        device.macAddresses = macText
            .split(whereSeparator: { $0 == "," || $0 == "\n" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { WakeOnLAN.parseMAC($0) != nil }
        let addressChanged = device.host != original.host || device.customPort != original.customPort || device.transport != original.transport
        if addressChanged {
            device.lastWorkingEndpoint = nil
            device.certificateFingerprint = nil
        }
        app.devices.update(device)
        if addressChanged, app.service.device?.id == device.id { app.service.connect(to: device) }
        dismiss()
    }
}
