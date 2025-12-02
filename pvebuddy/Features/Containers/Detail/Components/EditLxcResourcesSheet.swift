//
//  EditLxcResourcesSheet.swift
//  pvebuddy
//
//  Created by Oliver Steiner on 02.12.2025.
//

import SwiftUI

struct EditLxcResourcesSheet: View {
    @ObservedObject var viewModel: LxcDetailViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var cores: Int = 1
    @State private var memoryGB: Double = 1.0
    @State private var swapGB: Double = 0.0
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
                    Section(header: Text("Node capacity")) {
                        let nodeUsedGB = Double(ns.mem) / 1024 / 1024 / 1024
                        let nodeMaxGB = Double(max(1, ns.maxmem)) / 1024 / 1024 / 1024
                        let nodePct = ns.maxmem > 0 ? Int((Double(ns.mem) / Double(ns.maxmem)) * 100.0) : 0
                        Text(String(format: "RAM: %.1f / %.0f GB (%d%%)", nodeUsedGB, nodeMaxGB, nodePct))
                            .font(.footnote)
                        Text(String(format: "CPU wait: %.0f%%", ns.wait))
                            .font(.footnote)
                    }
                }

                Section(header: Text("CPU")) {
                    Stepper(value: $cores, in: 1...128) {
                        Text("Cores: \(cores)")
                    }
                    Text("Total CPU cores = \(cores)")
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
                        if swapGB > new { swapGB = new }
                    }

                    HStack {
                        Text("Swap (optional)")
                        Spacer()
                        Text(String(format: "%.1f GB", swapGB))
                    }
                    Slider(
                        value: $swapGB,
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
                                    if swapGB > memoryGB { swapGB = memoryGB }
                                }
                        }
                        VStack(alignment: .leading) {
                            Text("Swap GB").font(.caption)
                            TextField("Custom GB", value: $swapGB, format: .number)
                                .keyboardType(.decimalPad)
                                .onChange(of: swapGB) { _, new in
                                    let clamped = min(max(new, 0.0), memoryGB)
                                    swapGB = (clamped / memoryStep).rounded() * memoryStep
                                }
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("What is swap?")
                            .font(.headline)
                        Text("Swap allows the container to use disk space as additional memory when RAM is full. This can prevent out-of-memory errors but may reduce performance when actively used.")
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
                    .disabled(isSaving || (cores < 1) || (memoryGB < minMemoryGB))
                }
            }
            .onAppear {
                let currentMemGB = max(minMemoryGB, Double(viewModel.memMax) / 1024 / 1024 / 1024)
                cores = max(1, viewModel.container.cpus)
                let clamped = min(maxMemoryGB, currentMemGB)
                memoryGB = (clamped / memoryStep).rounded() * memoryStep
                swapGB = min(memoryGB, max(0.0, swapGB))
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
        let swapMiB = swapGB > 0 ? Int((swapGB * 1024.0).rounded()) : nil

        let err = await viewModel.updateResources(
            newCores: cores,
            newMemoryMiB: memMiB,
            newSwapMiB: swapMiB
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
