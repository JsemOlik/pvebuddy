import SwiftUI

struct SettingsView: View {
    @AppStorage("appearance_preference") private var appearancePreference: Int = 0 // 0: System, 1: Light, 2: Dark
    @AppStorage("pve_server_address") private var storedServerAddress: String = ""
    @AppStorage("pve_token_id") private var storedTokenID: String = ""
    @AppStorage("pve_token_secret") private var storedTokenSecret: String = ""
    @AppStorage("has_onboarded") private var hasOnboarded: Bool = false

    @State private var showClearDataAlert = false

    var body: some View {
        Form {
            Section(header: Text("General")) {
                NavigationLink {
                    AppearanceSettingsView()
                } label: {
                    Label("Appearance", systemImage: "paintbrush")
                }

                NavigationLink {
                    NotificationsSettingsView()
                } label: {
                    Label("Notifications", systemImage: "bell.badge")
                }

                NavigationLink {
                    EditServerInfoView()
                } label: {
                    Label("Edit server info", systemImage: "server.rack")
                }
            }

            Section {
                NavigationLink {
                    AboutView()
                } label: {
                    Label("About PVE Buddy", systemImage: "info.circle")
                }
            }

            Section {
                Button(role: .destructive) {
                    showClearDataAlert = true
                } label: {
                    Label {
                        Text("Clear all app data")
                    } icon: {
                        Image(systemName: "trash").foregroundStyle(.red)
                    }
                }
                .alert("Clear all app data?", isPresented: $showClearDataAlert) {
                    Button("Delete", role: .destructive) {
                        clearAllData()
                    }
                    Button("Cancel", role: .cancel) { }
                } message: {
                    Text("This will remove your saved server address and API token. You cannot undo this.")
                }
            } footer: {
                Text("Use with caution.")
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
    }

    private func clearAllData() {
        storedServerAddress = ""
        storedTokenID = ""
        storedTokenSecret = ""
        hasOnboarded = false
    }
}

#Preview {
    NavigationStack { SettingsView() }
}
