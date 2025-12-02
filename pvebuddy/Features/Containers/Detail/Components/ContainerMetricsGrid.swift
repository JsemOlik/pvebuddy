//
//  ContainerMetricsGrid.swift
//  pvebuddy
//
//  Created by Oliver Steiner on 01.12.2025.
//

import SwiftUI

struct ContainerMetricsGrid: View {
    let cpuPercent: Double
    let memUsedBytes: Int64
    let memTotalBytes: Int64
    let containerCPUs: Int
    @AppStorage("metric_cpu_absolute") private var showCpuAbsolute: Bool = false
    @AppStorage("metric_mem_absolute") private var showMemAbsolute: Bool = true

    var body: some View {
        let memUsedGB = Double(memUsedBytes) / 1024.0 / 1024.0 / 1024.0
        let memMaxGB = Double(max(1, memTotalBytes)) / 1024.0 / 1024.0 / 1024.0
        let memPct = memTotalBytes > 0
            ? min(100.0, max(0.0, (Double(memUsedBytes) / Double(memTotalBytes)) * 100.0))
            : 0

        return VStack(spacing: 16) {
            HStack(spacing: 16) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showCpuAbsolute.toggle()
                    }
                } label: {
                    liveMetricCard(
                        title: "CPU Usage",
                        value: cpuValueText(percent: cpuPercent, cpus: containerCPUs, absolute: showCpuAbsolute),
                        progress: cpuPercent / 100.0,
                        accentColor: .blue,
                        systemImage: "cpu"
                    )
                }
                .buttonStyle(.plain)

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showMemAbsolute.toggle()
                    }
                } label: {
                    liveMetricCard(
                        title: "RAM Usage",
                        value: memValueText(usedGB: memUsedGB, maxGB: memMaxGB, percent: memPct, absolute: showMemAbsolute),
                        progress: memPct / 100.0,
                        accentColor: .green,
                        systemImage: "memorychip"
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func cpuValueText(percent: Double, cpus: Int, absolute: Bool) -> String {
        if absolute {
            let used = Int(max(0, min(Double(cpus), round((percent / 100.0) * Double(cpus)))))
            return "\(used)/\(cpus) CPU"
        } else {
            return "\(Int(percent))%"
        }
    }

    private func memValueText(usedGB: Double, maxGB: Double, percent: Double, absolute: Bool) -> String {
        if absolute {
            return String(format: "%.2f/%.2f GB", usedGB, maxGB)
        } else {
            return "\(Int(percent))%"
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
                Text(value)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
                Spacer()
            }
            ProgressView(value: min(max(progress, 0.0), 1.0))
                .tint(accentColor)
                .progressViewStyle(.linear)
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
}
