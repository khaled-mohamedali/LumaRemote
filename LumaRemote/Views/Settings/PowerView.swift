import SwiftUI

struct PowerView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let service = app.service
        let macs = service.device?.macAddresses ?? []
        List {
            Section {
                Button(role: .destructive) { app.remote.press(.power) } label: {
                    Label("Turn TV off", systemImage: "power")
                }
                .disabled(!service.phase.isConnected || !service.capabilities.supports(.turnOff))
            } footer: {
                Text("Turning off over the network is supported by webOS. Turning back on is a different matter — see below.")
            }
            .listRowBackground(Theme.card)

            Section {
                Button { app.remote.wake() } label: {
                    Label("Wake TV (Wake-on-LAN)", systemImage: "sunrise")
                }
                .disabled(macs.isEmpty)
                LabeledContent("MAC address", value: macs.isEmpty ? "Not learned yet" : macs.joined(separator: ", "))
            } header: {
                Text("Turning on")
            } footer: {
                Text("""
                Your LG 32LM577BPUA (webOS 4.5, 2019) has a “Mobile TV On” setting. To wake it from your phone:
                1. On the TV: Settings › All Settings › General › Mobile TV On › turn on “Turn on via Wi-Fi”.
                2. Connect once while the TV is on so Luma Remote learns its MAC address.
                Limitations: iOS blocks broadcast packets unless an app has Apple’s multicast entitlement, so Luma Remote also sends the packet directly to the TV’s IP. That works while your router still remembers the TV — usually for a while after it turns off. If the TV has been off for hours, or is on Ethernet with Wake-on-LAN disabled, waking may not work; use the TV’s remote.
                """)
            }
            .listRowBackground(Theme.card)
        }
        .listStyle(.insetGrouped)
        .lumaScreen()
        .navigationTitle("Power & Wake")
    }
}
