import SwiftUI

struct AppearanceSettingsView: View {
    @AppStorage("appearance_preference") private var appearancePreference: Int = 0 // 0: System, 1: Light, 2: Dark

    var body: some View {
        Form {
            Section(footer: Text("Choose how PVE Buddy looks. System follows the device setting.")) {
                Picker("Appearance", selection: $appearancePreference) {
                    Text("System").tag(0)
                    Text("Light").tag(1)
                    Text("Dark").tag(2)
                }
                .pickerStyle(.inline)
            }
        }
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack { AppearanceSettingsView() }
}
