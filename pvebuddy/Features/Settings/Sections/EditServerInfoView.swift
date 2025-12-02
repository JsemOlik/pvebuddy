//
//  EditServerInfoView.swift
//  pvebuddy
//
//  Created by Oliver Steiner on 01.12.2025.
//

import SwiftUI

struct EditServerInfoView: View {
    @AppStorage("pve_server_address") private var storedServerAddress: String = ""
    @AppStorage("pve_token_id") private var storedTokenID: String = ""
    @AppStorage("pve_token_secret") private var storedTokenSecret: String = ""

    @State private var serverAddress: String = ""
    @State private var tokenID: String = ""
    @State private var tokenSecret: String = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section(header: Text("Server"), footer: Text("Enter the full URL, including https and port, e.g. https://pve.example.com:8006")) {
                TextField("https://pve.example.com:8006", text: $serverAddress)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
            }

            Section(header: Text("API token"), footer: Text("Token must have at least PVEAuditor permissions.")) {
                TextField("root@pam!pvebuddy", text: $tokenID)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("API token secret", text: $tokenSecret)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
        }
        .navigationTitle("Edit server info")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") { save() }
                    .disabled(!isValid)
            }
        }
        .onAppear {
            serverAddress = storedServerAddress
            tokenID = storedTokenID
            tokenSecret = storedTokenSecret
        }
    }

    private var isValid: Bool {
        !serverAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !tokenID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !tokenSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func save() {
        storedServerAddress = serverAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        storedTokenID = tokenID.trimmingCharacters(in: .whitespacesAndNewlines)
        storedTokenSecret = tokenSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        dismiss()
    }
}

#Preview {
    NavigationStack { EditServerInfoView() }
}
