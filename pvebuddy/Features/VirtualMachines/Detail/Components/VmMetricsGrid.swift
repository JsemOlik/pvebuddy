//
//  VmMetricsGrid.swift
//  pvebuddy
//
//  Created by Oliver Steiner on 01.12.2025.
//

import SwiftUI

struct VmMetricsGrid: View {
    let cpuPercent: Double
    let memUsedBytes: Int64
    let memTotalBytes: Int64

    var body: some View {
        let memUsedGB = Double(memUsedBytes) / 1024.0 / 1024.0 / 1024.0
        let memMaxGB = Double(max(1, memTotalBytes)) / 1024.0 / 1024.0 / 1024.0
        let memPct = memTotalBytes > 0
            ? min(100.0, max(0.0, (Double(memUsedBytes) / Double(memTotalBytes)) * 100.0))
            : 0

        return VStack(spacing: 16) {
            HStack(spacing: 16) {
                liveMetricCard(
                    title: "CPU Usage",
                    value: "\(Int(cpuPercent))%",
                    progress: cpuPercent / 100.0,
                    accentColor: .blue,
                    systemImage: "cpu"
                )

                liveMetricCard(
                    title: "RAM Usage",
                    value: String(format: "%.1f/%.0f GB", memUsedGB, memMaxGB),
                    progress: memPct / 100.0,
                    accentColor: .green,
                    systemImage: "memorychip"
                )
            }
        }
    }

    private func liveMetricCard(
        title: String,
        value: String,
        progress: Double,
        accentColor: Color,
        systemImage: String
    ) -> some View {
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
                Text(value).font(.system(size: 20, weight: .bold, design: .rounded))
                Spacer()
            }
            ProgressView(value: min(max(progress, 0.0), 1.0))
                .tint(accentColor)
                .progressViewStyle(.linear)
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
