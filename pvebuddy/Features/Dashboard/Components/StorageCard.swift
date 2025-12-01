//
//  StorageCard.swift
//  pvebuddy
//
//  Created by Oliver Steiner on 02.12.2025.
//

import SwiftUI

struct StorageCard: View {
    let storage: ProxmoxStorage
    
    var body: some View {
        let used = Double(storage.used)
        let total = Double(storage.total)
        let percentage = total > 0 ? max(0, min(100, (used / total) * 100.0)) : 0
        let freeBytes = storage.avail

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(storage.storage)
                        .font(.subheadline.weight(.semibold))

                    Text(storage.type.uppercased())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text("\(Int(percentage))%")
                    .font(.subheadline.weight(.semibold))
            }

            ProgressView(value: percentage / 100.0)
                .tint(.blue)
                .progressViewStyle(.linear)

            Text("\(ByteFormatter.format(storage.used)) used of \(ByteFormatter.format(storage.total)) • \(ByteFormatter.format(freeBytes)) free")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(.systemBackground),
                            Color(.secondarySystemBackground)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color(.separator).opacity(0.4), lineWidth: 0.5)
        )
    }
}
