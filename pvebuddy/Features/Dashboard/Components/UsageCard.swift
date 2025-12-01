//
//  UsageCard.swift
//  pvebuddy
//
//  Created by Oliver Steiner on 02.12.2025.
//

import SwiftUI

struct UsageCard: View {
    let title: String
    let value: Double
    let accentColor: Color
    let systemImage: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: systemImage)
                    .imageScale(.medium)
                    .foregroundStyle(accentColor)
                    .frame(width: 24, height: 24)

                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()
            }

            HStack(alignment: .lastTextBaseline) {
                Text("\(Int(value))%")
                    .font(.system(size: 28, weight: .bold, design: .rounded))

                Spacer()
            }

            ProgressView(value: value / 100.0)
                .tint(accentColor)
                .progressViewStyle(.linear)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color(.separator).opacity(0.5), lineWidth: 0.5)
        )
    }
}
