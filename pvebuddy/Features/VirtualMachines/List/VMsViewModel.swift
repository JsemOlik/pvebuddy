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
        NSLog("🏗️ VMsViewModel.init() called with address: %@", serverAddress)
        self.client = ProxmoxClient(baseAddress: serverAddress)
        NSLog("✅ ProxmoxClient initialized")
    }

    deinit {
        autoRefreshTask?.cancel()
    }

    func startAutoRefresh() {
        NSLog("🚀 startAutoRefresh() called")
        autoRefreshTask?.cancel()
        autoRefreshTask = Task {
            NSLog("🔁 Auto-refresh task started")
            // Load node list once when auto-refresh starts so the UI picker can populate.
            await loadNodes()
            NSLog("✅ Nodes loaded")

            while !Task.isCancelled {
                NSLog("⏱️ Auto-refresh tick")
                await refresh()
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
            NSLog("🛑 Auto-refresh task cancelled")
        }
    }

    func stopAutoRefresh() {
        autoRefreshTask?.cancel()
        autoRefreshTask = nil
    }

    func refresh() async {
        guard !isLoading else { 
            NSLog("⏭️ Refresh skipped - already loading")
            return 
        }
        isLoading = true
        errorMessage = nil
        
        NSLog("🔄 VMsViewModel.refresh() started")

        do {
            let fetchedVMs = try await client.fetchAllVMs()
            NSLog("✅ Fetched %d VMs", fetchedVMs.count)
            
            // Filter by selected node if one is chosen
            if let node = selectedNode, !node.isEmpty {
                self.vms = fetchedVMs.filter { $0.node == node }
                NSLog("📍 Filtered to %d VMs on node '%@'", self.vms.count, node)
            } else {
                self.vms = fetchedVMs
                NSLog("🌐 Using all %d VMs (no node filter)", self.vms.count)
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
            NSLog("💬 Error message set: %@", errorMessage ?? "nil")
        } catch {
            NSLog("❌ Unexpected error in refresh: %@", "\(error)")
            errorMessage = "Unexpected error: \(error.localizedDescription)"
        }

        isLoading = false
        NSLog("🔄 VMsViewModel.refresh() completed")
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
