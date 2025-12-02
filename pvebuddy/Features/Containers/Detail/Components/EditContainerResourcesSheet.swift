//
//  EditContainerResourcesSheet.swift
//  pvebuddy
//
//  Created by Oliver Steiner on 01.12.2025.
//

import SwiftUI

struct EditContainerResourcesSheet: View {
    @ObservedObject var viewModel: ContainerDetailViewModel
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
                
                // Load current swap value from config if available
                if let swapValue = viewModel.rawConfig["swap"], 
                   let swapMiB = Int(swapValue) {
                    let swapGBValue = Double(swapMiB) / 1024.0
                    swapGB = min(memoryGB, max(0.0, (swapGBValue / memoryStep).rounded() * memoryStep))
                } else {
                    // If config not loaded yet, load it and then update swap
                    Task {
                        if viewModel.rawConfig.isEmpty {
                            await viewModel.loadHardware()
                        }
                        
                        // Update swap after config is loaded
                        if let swapValue = viewModel.rawConfig["swap"], 
                           let swapMiB = Int(swapValue) {
                            let swapGBValue = Double(swapMiB) / 1024.0
                            await MainActor.run {
                                swapGB = min(memoryGB, max(0.0, (swapGBValue / memoryStep).rounded() * memoryStep))
                            }
                        }
                    }
                }
                
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


