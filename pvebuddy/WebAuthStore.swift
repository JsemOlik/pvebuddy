//
//  WebAuthStore.swift
//  pvebuddy
//
//  Created by Oliver Steiner on 01.12.2025.
//

import Foundation
import SwiftUI

struct WebAuthStore {
  @AppStorage("pve_web_username") private var usernameStore: String = ""
  @AppStorage("pve_web_password") private var passwordStore: String = ""
  @AppStorage("pve_web_realm") private var realmStore: String = "pam"

  var username: String { usernameStore }
  var password: String { passwordStore }
  var realm: String { realmStore.isEmpty ? "pam" : realmStore }

  var hasCreds: Bool {
    !usernameStore.trimmingCharacters(in: .whitespaces).isEmpty &&
      !passwordStore.isEmpty
  }

  func save(username: String, password: String, realm: String) {
    usernameStore = username
    passwordStore = password
    realmStore = realm.isEmpty ? "pam" : realm
  }

  func clear() {
    usernameStore = ""
    passwordStore = ""
    realmStore = "pam"
  }
}
