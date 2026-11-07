import SwiftUI

/// Picks which installed app goes in a remote shortcut slot. Lists only apps the TV
/// reports as installed.
struct AppPickerView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let slot: Int
    @State private var query = ""

    var body: some View {
        let service = app.service
        let currentID = app.preferences.shortcutAppIDs.indices.contains(slot) ? app.preferences.shortcutAppIDs[slot] : ""
        Group {
            if !service.phase.isConnected || service.launchPoints.isEmpty {
                ContentUnavailableView("No Apps", systemImage: "square.grid.2x2",
                                       description: Text("Connect to your TV to choose from its installed apps."))
            } else {
                List {
                    Section {
                        ForEach(filtered) { point in
                            Button {
                                app.remote.setShortcut(slot: slot, appID: point.id)
                                dismiss()
                            } label: {
                                HStack(spacing: 14) {
                                    TVImage(urls: point.iconURLs, fallbackSymbol: "app.fill")
                                        .frame(width: 36, height: 36)
                                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    Text(point.title).foregroundStyle(.white)
                                    Spacer()
                                    if point.id == currentID {
                                        Image(systemName: "checkmark").foregroundStyle(Theme.accent)
                                    }
                                }
                            }
                        }
                    } footer: {
                        Text("Picking an app that’s already in the other slot swaps the two.")
                    }
                    .listRowBackground(Theme.card)

                    if !currentID.isEmpty {
                        Section {
                            Button("Remove Shortcut", role: .destructive) {
                                app.remote.setShortcut(slot: slot, appID: nil)
                                dismiss()
                            }
                        }
                        .listRowBackground(Theme.card)
                    }
                }
                .listStyle(.insetGrouped)
                .searchable(text: $query, prompt: "Search apps")
            }
        }
        .lumaScreen()
        .navigationTitle("Shortcut \(slot + 1)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        }
    }

    private var filtered: [LaunchPoint] {
        let all = app.service.launchPoints.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        guard !query.isEmpty else { return all }
        return all.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }
}
