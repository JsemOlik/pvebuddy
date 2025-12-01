//
//  pvebuddyApp.swift
//  pvebuddy
//
//  Created by Oliver Steiner on 01.12.2025.
//

import SwiftUI

@main
struct pvebuddyApp: App {
    @AppStorage("has_onboarded") private var hasOnboarded: Bool = false
    var body: some Scene {
        WindowGroup {
            if hasOnboarded {
                MainTabView()
            } else {
                OnboardingView()
            }
        }
    }
}
