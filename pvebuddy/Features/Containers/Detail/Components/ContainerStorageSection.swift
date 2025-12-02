//
//  ContainerStorageSection.swift
//  pvebuddy
//
//  Created by Oliver Steiner on 02.12.2025.
//

import SwiftUI

struct ContainerStorageSection: View {
    let disks: [ContainerDetailViewModel.ContainerDisk]
    let loading: Bool
    let error: String?
    let onReload: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Storage")
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
                    Label("Error loading storage", systemImage: "exclamationmark.triangle.fill")
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
            } else if disks.isEmpty && !loading {
                VStack(spacing: 12) {
                    Image(systemName: "externaldrive")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                    Text("No storage attached")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
            } else {
                VStack(spacing: 12) {
                    ForEach(disks) { disk in
                        ContainerDiskItemView(disk: disk)
                    }
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color(.separator).opacity(0.3), lineWidth: 0.5)
        )
    }
}

private struct ContainerDiskItemView: View {
    let disk: ContainerDetailViewModel.ContainerDisk

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(disk.device.uppercased())
                            .font(.headline)
                        if disk.device == "rootfs" {
                            Text("ROOT")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule()
                                        .fill(Color.blue)
                                )
                        }
                    }
                    
                    Text(disk.storage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if let size = disk.size {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(ByteFormatter.format(size))
                            .font(.subheadline.weight(.semibold))
                        
                        Text("size")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let size = disk.size {
                let sizeGB = Double(size) / 1024 / 1024 / 1024
                Text(String(format: "Size: %.1f GB", sizeGB))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }
}

