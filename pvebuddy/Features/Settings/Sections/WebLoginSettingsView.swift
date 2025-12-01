//
//  WebLoginSettingsView.swift
//  pvebuddy
//
//  Created by Oliver Steiner on 01.12.2025.
//

import SwiftUI

struct WebLoginSettingsView: View {
  @State private var username: String = ""
  @State private var password: String = ""
  @State private var realm: String = "pam"

  private var store = WebAuthStore()

  var body: some View {
    Form {
      Section(footer: Text("These credentials are used to log in the embedded console WebView (PVEAuthCookie). API tokens alone cannot open the noVNC console.")) {
        TextField("Username (e.g. root)", text: $username)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled(true)
        SecureField("Password", text: $password)
        TextField("Realm (pam/pve)", text: $realm)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled(true)
      }

      Section {
        Button("Save") {
          store.save(username: username, password: password, realm: realm)
        }
        .disabled(username.trimmingCharacters(in: .whitespaces).isEmpty || password.isEmpty)

        Button("Clear", role: .destructive) {
          store.clear()
          username = ""
          password = ""
          realm = "pam"
        }
      }
    }
    .navigationTitle("Web Console Login")
    .onAppear {
      username = store.username
      password = store.password
      realm = store.realm
    }
  }
}
