//
//  Color+CardBackground.swift
//  pvebuddy
//
//  Created by Oliver Steiner on 02.12.2025.
//

import SwiftUI

extension Color {
    /// A color that provides better contrast for cards and elevated surfaces
    /// In light mode: Uses systemBackground (white) for clean look
    /// In dark mode: Uses secondarySystemBackground (lighter than grouped background) for better contrast
    static var cardBackground: Color {
        Color(UIColor { traitCollection in
            switch traitCollection.userInterfaceStyle {
            case .light:
                return .systemBackground // White in light mode
            case .dark:
                return .secondarySystemBackground // Lighter gray in dark mode
            case .unspecified:
                return .systemBackground
            @unknown default:
                return .systemBackground
            }
        })
    }
    
    /// A color for secondary card backgrounds (nested cards, alternate sections)
    /// Provides subtle variation from primary card background
    static var secondaryCardBackground: Color {
        Color(UIColor { traitCollection in
            switch traitCollection.userInterfaceStyle {
            case .light:
                return .secondarySystemBackground // Light gray in light mode
            case .dark:
                return .tertiarySystemBackground // Even lighter gray in dark mode
            case .unspecified:
                return .secondarySystemBackground
            @unknown default:
                return .secondarySystemBackground
            }
        })
    }
}

