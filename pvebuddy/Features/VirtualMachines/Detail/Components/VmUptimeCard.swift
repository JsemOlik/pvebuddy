//
//  VmUptimeCard.swift
//  pvebuddy
//
//  Created by Oliver Steiner on 01.12.2025.
//

import SwiftUI

struct VmUptimeCard: View {
    let uptimeSeconds: Int64

    var body: some View {
        let text = formatUptime(uptimeSeconds)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "clock")
                    .imageScale(.medium)
                    .foregroundStyle(.purple)
                    .frame(width: 24, height: 24)
                Text("Uptime")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            Text(text)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .monospacedDigit()
                .animation(.linear(duration: 0.2), value: text)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color(.separator).opacity(0.4), lineWidth: 0.5)
        )
    }

    private func formatUptime(_ seconds: Int64) -> String {
        let s = Int(seconds)
        let days = s / 86400
        let hrs = (s % 86400) / 3600
        let mins = (s % 3600) / 60
        let secs = s % 60
        if days > 0 {
            return "\(days)d \(String(format: "%02d:%02d:%02d", hrs, mins, secs))"
        } else {
            return String(format: "%02d:%02d:%02d", hrs, mins, secs)
        }
    }
}
