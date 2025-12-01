import SwiftUI

struct NotificationsSettingsView: View {
    @AppStorage("notifications_enabled") private var notificationsEnabled: Bool = false
    @AppStorage("notifications_status_changes") private var notifyStatusChanges: Bool = true
    @AppStorage("notifications_storage_threshold") private var notifyStorageThreshold: Bool = true

    var body: some View {
        Form {
            Section(footer: Text("Manage local notifications from PVE Buddy. You can fine-tune categories as features roll out.")) {
                Toggle(isOn: $notificationsEnabled) {
                    Label("Enable notifications", systemImage: "bell")
                }
                .tint(.blue)

                Toggle(isOn: $notifyStatusChanges) {
                    Label("Cluster status changes", systemImage: "bolt.trianglebadge.exclamationmark")
                }
                .disabled(!notificationsEnabled)

                Toggle(isOn: $notifyStorageThreshold) {
                    Label("Low storage threshold", systemImage: "externaldrive.trianglebadge.exclamationmark")
                }
                .disabled(!notificationsEnabled)
            }
        }
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack { NotificationsSettingsView() }
}
