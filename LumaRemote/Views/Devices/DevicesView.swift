import SwiftUI

struct DevicesView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            DevicesContent(showsSavedSection: true, onConnected: { dismiss() })
                .padding(20)
        }
        .lumaScreen()
        .navigationTitle("TVs")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
        }
    }
}

/// Saved TVs + discovery + manual entry. Also used on the first-launch screen.
struct DevicesContent: View {
    @Environment(AppModel.self) private var app
    var showsSavedSection: Bool
    var onConnected: (() -> Void)? = nil
    @State private var showManual = false

    var body: some View {
        let vm = app.devices
        VStack(spacing: 24) {
            if showsSavedSection && !vm.devices.isEmpty {
                VStack(spacing: 10) {
                    SectionHeader(title: "Saved TVs")
                    ForEach(vm.devices) { device in
                        SavedDeviceRow(device: device, onSelect: {
                            vm.select(device)
                            onConnected?()
                        })
                    }
                }
            }

            VStack(spacing: 10) {
                SectionHeader(title: "Add a TV")
                Button { showManual = true } label: {
                    actionRow(symbol: "keyboard", title: "Enter IP address",
                              subtitle: "Recommended. Find it on the TV under Settings › Network › Wi-Fi › Advanced.")
                }
                .buttonStyle(KeyPressStyle())

                Button { vm.discovery.isScanning ? vm.discovery.stop() : vm.discovery.start() } label: {
                    actionRow(symbol: "dot.radiowaves.left.and.right",
                              title: vm.discovery.isScanning ? "Stop scanning" : "Search this network",
                              subtitle: "Looks for LG TVs via Bonjour and a scan of your Wi-Fi network.")
                }
                .buttonStyle(KeyPressStyle())

                DiscoveryResults()
            }
        }
        .sheet(isPresented: $showManual) {
            NavigationStack {
                AddDeviceView(onSaved: {
                    showManual = false
                    onConnected?()
                })
            }
        }
        .onDisappear { vm.discovery.stop() }
    }

    private func actionRow(symbol: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 40, height: 40)
                .background(Circle().fill(Theme.accent.opacity(0.15)))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.semibold)).foregroundStyle(.white)
                Text(subtitle).font(.footnote).foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.textSecondary)
        }
        .padding(14)
        .card(radius: 18)
    }
}

struct SavedDeviceRow: View {
    @Environment(AppModel.self) private var app
    let device: SavedDevice
    let onSelect: () -> Void

    var body: some View {
        let isCurrent = app.service.device?.id == device.id
        HStack(spacing: 14) {
            Button(action: onSelect) {
                HStack(spacing: 14) {
                    Image(systemName: "tv")
                        .font(.system(size: 22))
                        .foregroundStyle(isCurrent ? Theme.accent : .white)
                        .frame(width: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(device.displayName).font(.body.weight(.semibold)).foregroundStyle(.white)
                        Text([device.host, device.modelName].compactMap { $0 }.joined(separator: " · "))
                            .font(.footnote).foregroundStyle(Theme.textSecondary)
                        Text(statusLine(isCurrent: isCurrent))
                            .font(.caption).foregroundStyle(isCurrent && app.service.phase.isConnected ? Theme.success : Theme.textSecondary)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(KeyPressStyle())

            NavigationLink {
                DeviceDetailView(deviceID: device.id)
            } label: {
                Image(systemName: "info.circle").font(.title3).foregroundStyle(Theme.accent)
            }
            .accessibilityLabel("Details for \(device.displayName)")
        }
        .padding(14)
        .card(radius: 18)
    }

    private func statusLine(isCurrent: Bool) -> String {
        if isCurrent { return app.remote.statusText }
        return app.devices.isPaired(device) ? "Paired" : "Not paired"
    }
}

struct DiscoveryResults: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let discovery = app.devices.discovery
        VStack(spacing: 10) {
            if discovery.isScanning {
                VStack(alignment: .leading, spacing: 8) {
                    Text(discovery.statusText ?? "Searching…").font(.footnote).foregroundStyle(Theme.textSecondary)
                    ProgressView(value: discovery.progress).tint(Theme.accent)
                }
                .padding(14)
                .card(radius: 18)
            } else if let status = discovery.statusText {
                Text(status).font(.footnote).foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            ForEach(discovery.found) { tv in
                HStack(spacing: 14) {
                    Image(systemName: "tv.badge.wifi").font(.system(size: 20)).foregroundStyle(Theme.accent).frame(width: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tv.name).font(.body.weight(.semibold)).foregroundStyle(.white)
                        Text([tv.host, tv.webOSVersion.map { "webOS \($0)" }, tv.source].compactMap { $0 }.joined(separator: " · "))
                            .font(.footnote).foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    if app.devices.isSaved(tv) {
                        Text("Saved").font(.footnote).foregroundStyle(Theme.textSecondary)
                    } else {
                        Button("Add") { app.devices.add(tv) }
                            .buttonStyle(.borderedProminent)
                            .tint(Theme.accentDeep)
                    }
                }
                .padding(14)
                .card(radius: 18)
            }
        }
    }
}
