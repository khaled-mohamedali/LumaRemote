import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var app
    @State private var tab: Tab = .remote

    enum Tab: Hashable { case remote, apps, inputs, more }

    var body: some View {
        Group {
            if app.deviceStore.devices.isEmpty {
                NavigationStack { WelcomeView() }
            } else {
                tabs
            }
        }
        .overlay(alignment: .bottom) {
            if let toast = app.remote.toast {
                ToastView(toast: toast)
                    .padding(.bottom, 92)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .onTapGesture { app.remote.dismissToast() }
                    .id(toast.id)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: app.remote.toast)
        .sheet(isPresented: pairingBinding) {
            PairingPromptView()
                .presentationDetents([.large])
                .presentationBackground(Theme.card)
                .interactiveDismissDisabled()
        }
        .onChange(of: app.network.restoredCount) { _, _ in app.service.networkRestored() }
    }

    private var tabs: some View {
        TabView(selection: $tab) {
            RemoteView()
                .tabItem { Label("Remote", systemImage: "house.fill") }
                .tag(Tab.remote)
            AppsView()
                .tabItem { Label("Apps", systemImage: "square.grid.2x2.fill") }
                .tag(Tab.apps)
            InputsView()
                .tabItem { Label("Inputs", systemImage: "tv") }
                .tag(Tab.inputs)
            MoreView()
                .tabItem { Label("More", systemImage: "ellipsis") }
                .tag(Tab.more)
        }
        .toolbarBackground(Theme.background, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
    }

    private var pairingBinding: Binding<Bool> {
        Binding(
            get: {
                switch app.service.phase {
                case .awaitingPairing, .awaitingPin: return true
                default: return false
                }
            },
            set: { _ in }
        )
    }
}

/// First launch: no TVs yet.
struct WelcomeView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                Image(systemName: "av.remote.fill")
                    .font(.system(size: 54))
                    .foregroundStyle(Theme.accent)
                    .padding(.top, 40)
                Text("Luma Remote")
                    .font(.largeTitle.bold())
                Text("Control your LG TV over Wi-Fi. No ads, no accounts, nothing leaves your home network.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal)
                DevicesContent(showsSavedSection: false)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
        .lumaScreen()
    }
}
