import SwiftUI

/// Installed apps, exactly as the TV reports them (`listLaunchPoints`). Nothing is
/// hardcoded: if YouTube is installed, it appears; if not, it doesn't.
struct AppsView: View {
    @Environment(AppModel.self) private var app
    @State private var query = ""
    private let columns = [GridItem(.adaptive(minimum: 96, maximum: 130), spacing: 16)]

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Apps")
                .lumaScreen()
                .toolbarBackground(Theme.background, for: .navigationBar)
        }
    }

    @ViewBuilder private var content: some View {
        let service = app.service
        if !service.phase.isConnected {
            ContentUnavailableView("Not Connected", systemImage: "tv.slash",
                                   description: Text("Connect to your TV to see its apps."))
        } else if !service.capabilities.supports(.launchPoints) {
            ContentUnavailableView("Apps Unavailable", systemImage: "square.grid.2x2",
                                   description: Text("This TV’s firmware doesn’t share its app list over the network."))
        } else if !service.appsLoaded {
            ProgressView("Loading apps…").tint(Theme.accent)
        } else if filtered.isEmpty {
            ContentUnavailableView.search(text: query)
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(filtered) { point in
                        AppTile(point: point, isForeground: point.id == service.foregroundAppID) {
                            app.remote.launch(point)
                        }
                    }
                }
                .padding(20)
            }
            .searchable(text: $query, prompt: "Search apps")
        }
    }

    private var filtered: [LaunchPoint] {
        let all = app.service.launchPoints
        guard !query.isEmpty else { return all }
        return all.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }
}

struct AppTile: View {
    let point: LaunchPoint
    let isForeground: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                TVImage(urls: point.iconURLs, fallbackSymbol: "app.fill")
                    .frame(width: 64, height: 64)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.card))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(isForeground ? Theme.accent : Theme.stroke, lineWidth: isForeground ? 2 : 1)
                    )
                Text(point.title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
        }
        .buttonStyle(KeyPressStyle())
        .accessibilityLabel(isForeground ? "\(point.title), currently open" : point.title)
    }
}
