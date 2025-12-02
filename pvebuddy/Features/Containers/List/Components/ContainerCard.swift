//
//  ContainerCard.swift
//  pvebuddy
//
//  Created by Oliver Steiner on 01.12.2025.
//

import SwiftUI

struct ContainerCard: View {
    let container: ProxmoxContainer
    
    var body: some View {
        let memUsedGB = Double(container.mem) / 1024.0 / 1024.0 / 1024.0
        let memMaxGB = Double(container.maxmem) / 1024.0 / 1024.0 / 1024.0

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                if let imageName = DistroImageMapper.imageName(from: container.tags) {
                    Image(imageName)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 28, height: 28)
                        .clipShape(Circle())
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(container.name).font(.subheadline.weight(.semibold))
                    Text(container.node).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                ContainerStatusBadge(status: container.status)
            }

            HStack(spacing: 16) {
                HStack(spacing: 6) {
                    Image(systemName: "cpu").font(.caption).foregroundStyle(.blue)
                    Text("0/\(container.cpus) cores")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 6) {
                    Image(systemName: "memorychip").font(.caption).foregroundStyle(.green)
                    Text(String(format: "%.1f/%.0f GB", memUsedGB, memMaxGB))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color(UIColor.separator).opacity(0.4), lineWidth: 0.5)
        )
    }
}
