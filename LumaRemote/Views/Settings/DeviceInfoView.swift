import SwiftUI

struct DeviceInfoView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let service = app.service
        let info = service.info
        let device = service.device
        List {
            Section("Television") {
                item("Name", device?.displayName)
                item("Model", info.modelName ?? device?.modelName)
                item("Platform", info.productName ?? info.deviceOS)
                item("webOS version", info.webOSVersion)
                item("Firmware", info.firmwareVersion ?? device?.firmwareVersion)
                item("Receiver", info.receiverType)
                item("Country", info.country)
            }
            .listRowBackground(Theme.card)

            Section("Network") {
                item("IP address", device?.host)
                item("Connection", service.endpoint?.label)
                item("Status", app.remote.statusText)
                item("Power state", service.powerState)
                item("Wi-Fi MAC", info.macWiFi)
                item("Ethernet MAC", info.macWired)
            }
            .listRowBackground(Theme.card)

            Section {
                capability("Button input (pointer socket)", service.capabilities.pointerInput)
                ForEach(trackedEndpoints, id: \.self) { e in
                    capability(e.label, service.phase.isConnected ? service.capabilities.supports(e) : nil)
                }
            } header: {
                Text("Detected capabilities")
            } footer: {
                Text("Detected from the TV’s own replies. Features the TV reports as missing are hidden from the remote.")
            }
            .listRowBackground(Theme.card)

            if !info.services.isEmpty {
                Section("Services reported by the TV") {
                    Text(info.services.joined(separator: ", "))
                        .font(.caption.monospaced())
                        .foregroundStyle(Theme.textSecondary)
                }
                .listRowBackground(Theme.card)
            }
        }
        .listStyle(.insetGrouped)
        .lumaScreen()
        .navigationTitle("Device Information")
    }

    private var trackedEndpoints: [SSAPEndpoint] {
        [.turnOff, .volumeUp, .setMute, .channelUp, .externalInputs, .switchInput, .launchPoints,
         .launch, .play, .insertText, .powerState]
    }

    @ViewBuilder private func item(_ title: String, _ value: String?) -> some View {
        LabeledContent(title, value: (value?.isEmpty == false ? value : nil) ?? "—")
    }

    private func capability(_ title: String, _ supported: Bool?) -> some View {
        HStack {
            Text(title)
            Spacer()
            switch supported {
            case .some(true): Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.success)
            case .some(false): Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.textSecondary)
            case .none: Text("Unknown").foregroundStyle(Theme.textSecondary)
            }
        }
    }
}

extension SSAPEndpoint {
    var label: String {
        switch self {
        case .turnOff: return "Power off"
        case .volumeUp: return "Volume"
        case .setMute: return "Mute"
        case .channelUp: return "Channels"
        case .externalInputs: return "Input list"
        case .switchInput: return "Input switching"
        case .launchPoints: return "App list"
        case .launch: return "App launching"
        case .play: return "Media controls"
        case .insertText: return "Text input"
        case .powerState: return "Power state"
        default: return rawValue
        }
    }
}

struct PairingInfoView: View {
    @Environment(AppModel.self) private var app
    @State private var confirmForget = false

    var body: some View {
        let device = app.service.device
        List {
            Section {
                LabeledContent("Status", value: app.service.isPaired ? "Paired" : "Not paired")
                LabeledContent("Key storage", value: "iOS Keychain (this device only)")
                if let manifest = device?.registrationManifest {
                    LabeledContent("Permission manifest", value: manifest == "legacySigned" ? "Legacy (signed)" : "Current")
                }
                if let fp = device?.certificateFingerprint {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("TV certificate (SHA-256)")
                        Text(fp).font(.caption2.monospaced()).foregroundStyle(Theme.textSecondary)
                    }
                }
            } footer: {
                Text("When you first connect, the TV asks you to accept Luma Remote and then issues a pairing key. Luma Remote stores that key in the Keychain and never shows or logs it. Secure connections use trust-on-first-use: the TV’s certificate is remembered and any different certificate is refused.")
            }
            .listRowBackground(Theme.card)

            if let device, app.service.isPaired {
                Section {
                    Button("Forget pairing", role: .destructive) { confirmForget = true }
                } footer: {
                    Text("To also revoke access on the TV, remove Luma Remote from the TV’s list of connected devices (location varies by firmware; often Settings › General › Mobile TV On or External Devices).")
                }
                .listRowBackground(Theme.card)
                .confirmationDialog("Forget pairing?", isPresented: $confirmForget, titleVisibility: .visible) {
                    Button("Forget", role: .destructive) { app.service.forgetPairing(for: device.id) }
                }
            }
        }
        .listStyle(.insetGrouped)
        .lumaScreen()
        .navigationTitle("Pairing")
    }
}
