//
//  VMsViewModel.swift
//  pvebuddy
//
//  Created by Oliver Steiner on 01.12.2025.
//

import Foundation
import SwiftUI
import Combine
import os

@MainActor
final class VMsViewModel: ObservableObject {
    @Published var vms: [ProxmoxVM] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var nodes: [String] = []
    @Published var selectedNode: String? = nil // nil == Datacenter (all nodes)

    private let client: ProxmoxClient
    private var autoRefreshTask: Task<Void, Never>?

    init(serverAddress: String) {
        self.client = ProxmoxClient(baseAddress: serverAddress)
    }

    deinit {
        autoRefreshTask?.cancel()
    }

    func startAutoRefresh() {
        autoRefreshTask?.cancel()
        autoRefreshTask = Task {
            // Load node list once when auto-refresh starts so the UI picker can populate.
            await loadNodes()

            while !Task.isCancelled {
                await refresh()
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
    }

    func stopAutoRefresh() {
        autoRefreshTask?.cancel()
        autoRefreshTask = nil
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil

        do {
            let fetchedVMs = try await client.fetchAllVMs()
            
            // Filter by selected node if one is chosen
            if let node = selectedNode, !node.isEmpty {
                self.vms = fetchedVMs.filter { $0.node == node }
            } else {
                self.vms = fetchedVMs
            }
        } catch let error as ProxmoxClientError {
            NSLog("❌ ProxmoxClientError in refresh: %@", "\(error)")
            switch error {
            case .invalidURL:
                errorMessage = "The server address looks invalid. Make sure it includes the scheme, e.g. https://pve.example.com:8006."
            case .requestFailed(let statusCode, _):
                if statusCode == 401 || statusCode == 403 {
                    errorMessage = "Authentication failed. Please double-check your API token ID and secret."
                } else if statusCode == 0 || statusCode == -1 {
                    errorMessage = "Unable to reach your Proxmox server. Check the address, network, and HTTPS certificate."
                } else {
                    errorMessage = "Server returned an error (HTTP \(statusCode)). See the Xcode console for details."
                }
            case .decodingFailed:
                errorMessage = "Received data in an unexpected format. Make sure your Proxmox version is supported."
            case .noNodesFound:
                errorMessage = "No VMs were returned by the Proxmox API. Check that your token has permission to view VMs."
            }
        } catch {
            NSLog("❌ Unexpected error in refresh: %@", "\(error)")
            errorMessage = "Unexpected error: \(error.localizedDescription)"
        }

        isLoading = false
    }

    /// Load available node names for the cluster so the UI can present a picker.
    func loadNodes() async {
        do {
            let names = try await client.fetchAllNodeNames()
            // Keep order from server; don't include a "Datacenter" sentinel here — the UI will present that.
            self.nodes = names
        } catch {
            print("❌ Failed to load node names: \(error)")
            self.nodes = []
        }
    }
}
