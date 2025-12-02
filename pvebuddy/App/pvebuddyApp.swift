//
//  pvebuddyApp.swift
//  pvebuddy
//
//  Created by Oliver Steiner on 01.12.2025.
//

// Project Name: pvebuddy
// Copyright (C) 2025  Oliver Steiner hello@jsemolik.dev

// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.

// You should have received a copy of the GNU General Public License
// along with this program. If not, see https://www.gnu.org/licenses/.

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
