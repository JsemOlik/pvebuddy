//
//  ContainerUsageGraphsView.swift
//  pvebuddy
//
//  Created by Oliver Steiner on 01.12.2025.
//

import SwiftUI
import Charts

struct ContainerUsageGraphsView: View {
    let chartPoints: [ContainerDetailViewModel.ChartPoint]
    
    private var recentPoints: [ContainerDetailViewModel.ChartPoint] {
        let cutoff = Date().addingTimeInterval(-60) // Past 1 minute
        return chartPoints.filter { $0.date >= cutoff }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Resource Usage (Last Minute)")
                .font(.headline.weight(.semibold))
            
            // CPU Graph
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "cpu")
                        .foregroundStyle(.blue)
                        .font(.subheadline)
                    Text("CPU Usage")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    if let last = recentPoints.last {
                        Text("\(Int(last.cpuPercent))%")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.blue)
                    }
                }
                
                if recentPoints.isEmpty {
                    VStack(spacing: 8) {
                        Text("No data yet")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Data will appear as the container runs")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(height: 120)
                    .frame(maxWidth: .infinity)
                } else {
                    Chart {
                        ForEach(recentPoints) { point in
                            LineMark(
                                x: .value("Time", point.date),
                                y: .value("CPU", point.cpuPercent)
                            )
                            .foregroundStyle(.blue)
                            .interpolationMethod(.catmullRom)
                            
                            AreaMark(
                                x: .value("Time", point.date),
                                y: .value("CPU", point.cpuPercent)
                            )
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color.blue.opacity(0.3), Color.blue.opacity(0.05)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                        }
                    }
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                            AxisGridLine()
                            AxisValueLabel(format: .dateTime.hour().minute().second())
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading, values: .automatic(desiredCount: 5)) { value in
                            AxisGridLine()
                            AxisValueLabel {
                                if let intValue = value.as(Int.self) {
                                    Text("\(intValue)%")
                                }
                            }
                        }
                    }
                    .chartYScale(domain: 0...100)
                    .frame(height: 120)
                }
            }
            
            Divider()
            
            // Memory Graph
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "memorychip")
                        .foregroundStyle(.green)
                        .font(.subheadline)
                    Text("Memory Usage")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    if let last = recentPoints.last, last.memTotalBytes > 0 {
                        let memPercent = (Double(last.memUsedBytes) / Double(last.memTotalBytes)) * 100.0
                        Text("\(Int(memPercent))%")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.green)
                    }
                }
                
                if recentPoints.isEmpty {
                    VStack(spacing: 8) {
                        Text("No data yet")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Data will appear as the container runs")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(height: 120)
                    .frame(maxWidth: .infinity)
                } else {
                    Chart {
                        ForEach(recentPoints) { point in
                            let memPercent = point.memTotalBytes > 0 
                                ? (Double(point.memUsedBytes) / Double(point.memTotalBytes)) * 100.0 
                                : 0.0
                            
                            LineMark(
                                x: .value("Time", point.date),
                                y: .value("Memory", memPercent)
                            )
                            .foregroundStyle(.green)
                            .interpolationMethod(.catmullRom)
                            
                            AreaMark(
                                x: .value("Time", point.date),
                                y: .value("Memory", memPercent)
                            )
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color.green.opacity(0.3), Color.green.opacity(0.05)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                        }
                    }
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                            AxisGridLine()
                            AxisValueLabel(format: .dateTime.hour().minute().second())
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading, values: .automatic(desiredCount: 5)) { value in
                            AxisGridLine()
                            AxisValueLabel {
                                if let intValue = value.as(Int.self) {
                                    Text("\(intValue)%")
                                }
                            }
                        }
                    }
                    .chartYScale(domain: 0...100)
                    .frame(height: 120)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color(.separator).opacity(0.3), lineWidth: 0.5)
        )
    }
}

