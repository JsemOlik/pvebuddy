//
//  VmHardwareSection.swift
//  pvebuddy
//
//  Created by Oliver Steiner on 01.12.2025.
//

import SwiftUI

struct VmHardwareSection: View {
    let isExpanded: Binding<Bool>
    let loading: Bool
    let error: String?
    let hardware: [VMDetailViewModel.HardwareSection]
    let onReload: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            DisclosureGroup(isExpanded: isExpanded) {
                if loading {
                    ProgressView().padding(.vertical, 8)
                } else if let err = error {
                    Text(err)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                } else if hardware.isEmpty {
                    Text("No hardware information.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                } else {
                    VStack(spacing: 12) {
                        ForEach(hardware) { section in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(section.title).font(.subheadline.weight(.semibold))
                                ForEach(section.items) { item in
                                    HStack {
                                        Text(item.key).font(.footnote).foregroundStyle(.secondary)
                                        Spacer()
                                        Text(item.value).font(.footnote)
                                    }
                                }
                            }
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color(.systemBackground))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(Color(.separator).opacity(0.35), lineWidth: 0.5)
                            )
                        }
                    }
                    .padding(.top, 8)
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "wrench.and.screwdriver").foregroundStyle(.blue)
                    Text("Hardware").font(.headline)
                    Spacer()
                    Button { onReload() } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(.systemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color(.separator).opacity(0.4), lineWidth: 0.5)
            )
        }
    }
}
