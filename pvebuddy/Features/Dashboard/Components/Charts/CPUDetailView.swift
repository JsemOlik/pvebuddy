//
//  CPUDetailView.swift
//  pvebuddy
//
//  Created by Oliver Steiner on 01.12.2025.
//

import SwiftUI
import Charts

struct CPUDetailView: View {
    let samples: [DashboardViewModel.Sample]

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
                Capsule()
                    .frame(width: 36, height: 5)
                    .foregroundStyle(Color.secondary.opacity(0.4))
                    .padding(.top, 8)

                Text("CPU Usage")
                    .font(.title2.weight(.semibold))

                if let last = samples.last {
                    Text("Current: \(Int(last.cpuPercent))%")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }

                let cutoff = Date().addingTimeInterval(-120)
                let recent = samples.filter { $0.date >= cutoff }

                Chart {
                    ForEach(recent) { s in
                        LineMark(
                            x: .value("Time", s.date),
                            y: .value("CPU", s.cpuPercent)
                        )
                        .interpolationMethod(.catmullRom)

                        AreaMark(
                            x: .value("Time", s.date),
                            y: .value("CPU", s.cpuPercent)
                        )
                        .opacity(0.15)
                    }
                }
                .chartYScale(domain: 0...100)
                .frame(height: 260)

                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 48)
        }
    }
}
