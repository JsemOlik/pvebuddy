//
//  ContainerStatusBadge.swift
//  pvebuddy
//
//  Created by Oliver Steiner on 01.12.2025.
//

import SwiftUI

struct ContainerStatusBadge: View {
    let status: String
    
    private var colors: (bg: Color, text: Color, icon: String) {
        switch status.lowercased() {
        case "running": return (.green, .green, "play.circle.fill")
        case "stopped": return (.red, .red, "stop.circle.fill")
        case "suspended", "paused": return (.orange, .orange, "pause.circle.fill")
        default: return (.gray, .gray, "questionmark.circle.fill")
        }
    }
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: colors.icon).font(.caption.weight(.semibold))
            Text(status.capitalized).font(.caption.weight(.semibold))
        }
        .foregroundStyle(colors.text)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(colors.bg.opacity(0.15))
        .cornerRadius(6)
    }
}
