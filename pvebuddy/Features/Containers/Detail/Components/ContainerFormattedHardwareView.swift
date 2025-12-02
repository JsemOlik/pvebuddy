//
//  ContainerFormattedHardwareView.swift
//  pvebuddy
//
//  Created by Oliver Steiner on 02.12.2025.
//

import SwiftUI

struct ContainerFormattedHardwareView: View {
    let hardware: [ContainerDetailViewModel.HardwareSection]
    let loading: Bool
    let error: String?
    let onReload: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Resources")
                    .font(.title2.weight(.bold))
                Spacer()
                if loading {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Button(action: onReload) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.blue)
                    }
                }
            }

            if let error = error {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Error loading resources", systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(.systemBackground))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.orange.opacity(0.3), lineWidth: 0.5)
                )
            } else if hardware.isEmpty && !loading {
                VStack(spacing: 12) {
                    Image(systemName: "wrench.and.screwdriver")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                    Text("No resource information")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
            } else {
                VStack(spacing: 12) {
                    ForEach(hardware) { section in
                        HardwareCategoryView(section: section)
                    }
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color(.separator).opacity(0.3), lineWidth: 0.5)
        )
    }
}

private struct HardwareCategoryView: View {
    let section: ContainerDetailViewModel.HardwareSection
    @State private var isExpanded: Bool = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(section.items) { item in
                    HStack {
                        Text(item.key)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(item.value)
                            .font(.subheadline.weight(.medium))
                            .multilineTextAlignment(.trailing)
                    }
                    .padding(.vertical, 4)
                    
                    if item.id != section.items.last?.id {
                        Divider()
                    }
                }
            }
            .padding(.top, 8)
        } label: {
            HStack {
                Image(systemName: iconForSection(section.title))
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.blue)
                    .frame(width: 24)
                
                Text(section.title)
                    .font(.headline)
                
                Spacer()
                
                Text("\(section.items.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color.secondaryCardBackground)
                    )
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.secondaryCardBackground)
        )
    }

    private func iconForSection(_ title: String) -> String {
        switch title {
        case "CPU & Memory": return "cpu"
        case "Boot": return "power"
        case "Storage": return "externaldrive"
        case "Network": return "network"
        case "LXC": return "cube.transparent"
        case "Cloud-Init": return "cloud"
        default: return "gearshape"
        }
    }
}

