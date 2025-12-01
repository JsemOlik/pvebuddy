//
//  EditResourcesSheet.swift
//  pvebuddy
//
//  Created by Oliver Steiner on 01.12.2025.
//

import SwiftUI

struct EditResourcesSheet: View {
    @ObservedObject var viewModel: VMDetailViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var cores: Int = 1
    @State private var sockets: Int = 1
    @State private var memoryGB: Double = 1.0
    @State private var balloonGB: Double = 0.0
    @State private var isSaving = false
    @State private var saveError: String?

    private let minMemoryGB: Double = 0.5
    private let maxMemoryGB: Double = 64
    private let memoryStep: Double = 0.5

    @State private var nodeTicker: Timer?

    var body: some View {
        NavigationStack {
            Form {
                if let ns = viewModel.nodeStatus {
                    Section(header: Text("Node capacity (live)")) {
                        let nodeUsedGB = Double(ns.mem) / 1024 / 1024 / 1024
                        let nodeMaxGB = Double(max(1, ns.maxmem)) / 1024 / 1024 / 1024
                        let nodePct = ns.maxmem > 0 ? Int((Double(ns.mem) / Double(ns.maxmem)) * 100.0) : 0
                        Text(String(format: "RAM: %.1f / %.0f GB (%d%%)", nodeUsedGB, nodeMaxGB, nodePct))
                            .font(.footnote)
                        Text(String(format: "CPU wait: %.0f%%", ns.wait))
                            .font(.footnote)
                    }
                }

                Section(header: Text("vCPU")) {
                    Stepper(value: $cores, in: 1...128) {
                        Text("Cores: \(cores)")
                    }
                    Stepper(value: $sockets, in: 1...16) {
                        Text("Sockets: \(sockets)")
                    }
                    Text("Total vCPU = cores × sockets = \(cores * sockets)")
                        .font(.footnote).foregroundStyle(.secondary)
                }

                Section(header: Text("Memory")) {
                    HStack {
                        Text("Memory")
                        Spacer()
                        Text(String(format: "%.1f GB", memoryGB))
                    }
                    Slider(
                        value: $memoryGB,
                        in: minMemoryGB...maxMemoryGB,
                        step: memoryStep
                    )
                    .onChange(of: memoryGB) { _, new in
                        if balloonGB > new { balloonGB = new }
                    }

                    HStack {
                        Text("Balloon (optional)")
                        Spacer()
                        Text(String(format: "%.1f GB", balloonGB))
                    }
                    Slider(
                        value: $balloonGB,
                        in: 0.0...max(0.0, memoryGB),
                        step: memoryStep
                    )

                    HStack(spacing: 12) {
                        VStack(alignment: .leading) {
                            Text("Memory GB").font(.caption)
                            TextField("Custom GB", value: $memoryGB, format: .number)
                                .keyboardType(.decimalPad)
                                .onChange(of: memoryGB) { _, new in
                                    let clamped = min(max(new, minMemoryGB), maxMemoryGB)
                                    memoryGB = (clamped / memoryStep).rounded() * memoryStep
                                    if balloonGB > memoryGB { balloonGB = memoryGB }
                                }
                        }
                        VStack(alignment: .leading) {
                            Text("Balloon GB").font(.caption)
                            TextField("Custom GB", value: $balloonGB, format: .number)
                                .keyboardType(.decimalPad)
                                .onChange(of: balloonGB) { _, new in
                                    let clamped = min(max(new, 0.0), memoryGB)
                                    balloonGB = (clamped / memoryStep).rounded() * memoryStep
                                }
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("What is balloon RAM?")
                            .font(.headline)
                        Text("Ballooning lets the host reclaim some of the VM's memory when the VM doesn't need it, by inflating a 'balloon' driver inside the guest. When the VM needs memory again, the balloon deflates and returns memory. This requires the QEMU guest agent/balloon driver in the guest OS and may not be as predictable as fixed memory.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 6)
                }

                if let err = saveError {
                    Section {
                        Text(err).foregroundStyle(.red).font(.footnote)
                    }
                }
            }
            .navigationTitle("Edit Resources")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save") {
                        Task { await save() }
                    }
                    .disabled(isSaving || (cores < 1) || (sockets < 1) || (memoryGB < minMemoryGB))
                }
            }
            .onAppear {
                let currentMemGB = max(minMemoryGB, Double(viewModel.memMax) / 1024 / 1024 / 1024)
                cores = max(1, viewModel.vm.cpus)
                sockets = 1
                let clamped = min(maxMemoryGB, currentMemGB)
                memoryGB = (clamped / memoryStep).rounded() * memoryStep
                balloonGB = min(memoryGB, max(0.0, balloonGB))
                startLiveNodeTicker()
            }
            .onDisappear {
                stopLiveNodeTicker()
            }
        }
    }

    private func save() async {
        isSaving = true
        saveError = nil
        let memMiB = Int((memoryGB * 1024.0).rounded())
        let balloonMiB = balloonGB > 0 ? Int((balloonGB * 1024.0).rounded()) : nil

        let err = await viewModel.updateResources(
            newCores: cores,
            newSockets: sockets,
            newMemoryMiB: memMiB,
            newBalloonMiB: balloonMiB
        )
        isSaving = false
        if let err { saveError = err } else { dismiss() }
    }

    private func startLiveNodeTicker() {
        stopLiveNodeTicker()
        nodeTicker = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            Task { await viewModel.loadNodeStatus() }
        }
        RunLoop.main.add(nodeTicker!, forMode: .common)
    }

    private func stopLiveNodeTicker() {
        nodeTicker?.invalidate()
        nodeTicker = nil
    }
}
