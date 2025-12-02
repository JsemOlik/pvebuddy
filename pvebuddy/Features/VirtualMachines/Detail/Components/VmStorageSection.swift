//
//  VmStorageSection.swift
//  pvebuddy
//
//  Created by Oliver Steiner on 02.12.2025.
//

import SwiftUI

struct VmStorageSection: View {
    let storages: [ProxmoxStorage]
    let loading: Bool
    let error: String?
    let onReload: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Storage Devices")
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
            } else if storages.isEmpty && !loading {
                VStack(spacing: 12) {
                    Image(systemName: "externaldrive")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                    Text("No storage devices found")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
            } else {
                VStack(spacing: 12) {
                    ForEach(storages) { storage in
                        StorageItemView(storage: storage)
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

private struct StorageItemView: View {
    let storage: ProxmoxStorage

    var body: some View {
        let used = Double(storage.used)
        let total = Double(storage.total)
        let percentage = total > 0 ? max(0, min(100, (used / total) * 100.0)) : 0
        let availGB = Double(storage.avail) / 1024 / 1024 / 1024
        let totalGB = Double(storage.total) / 1024 / 1024 / 1024
        let usedGB = Double(storage.used) / 1024 / 1024 / 1024

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(storage.storage)
                        .font(.headline)
                    
                    Text(storage.type.uppercased())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text(String(format: "%.1f GB", availGB))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(percentage > 80 ? .orange : .primary)
                    
                    Text("available")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            ProgressView(value: percentage / 100.0)
                .tint(percentage > 80 ? .orange : (percentage > 60 ? .yellow : .blue))
                .progressViewStyle(.linear)

            HStack {
                Text(String(format: "%.1f GB used", usedGB))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                Text(String(format: "%.1f GB total", totalGB))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                Text("\(Int(percentage))%")
                    .font(.footnote.weight(.medium))
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

