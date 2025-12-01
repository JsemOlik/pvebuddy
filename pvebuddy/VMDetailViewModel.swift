import Foundation
import SwiftUI
import Combine

@MainActor
final class VMDetailViewModel: ObservableObject {
    @Published var vm: ProxmoxVM
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    private let client: ProxmoxClient
    private let initialVM: ProxmoxVM
    private var autoRefreshTask: Task<Void, Never>?

    init(vm: ProxmoxVM, serverAddress: String) {
        self.initialVM = vm
        self.vm = vm
        self.client = ProxmoxClient(baseAddress: serverAddress)
    }

    deinit {
        autoRefreshTask?.cancel()
    }

    func startAutoRefresh() {
        NSLog("🚀 VMDetailViewModel.startAutoRefresh() called for VM %@", initialVM.vmid)
        autoRefreshTask?.cancel()
        autoRefreshTask = Task {
            NSLog("🔁 VM detail auto-refresh task started")
            while !Task.isCancelled {
                NSLog("⏱️ VM detail auto-refresh tick for VM %@", self.initialVM.vmid)
                await self.refresh()
                try? await Task.sleep(for: .seconds(3))
            }
            NSLog("🛑 VM detail auto-refresh task cancelled")
        }
    }

    func stopAutoRefresh() {
        NSLog("🛑 VMDetailViewModel.stopAutoRefresh() called for VM %@", initialVM.vmid)
        autoRefreshTask?.cancel()
        autoRefreshTask = nil
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil

        NSLog("🔄 VMDetailViewModel.refresh() started for VM %@", initialVM.vmid)

        do {
            let detail = try await client.fetchVMDetail(node: initialVM.node, vmid: initialVM.vmid)
            
            // Update the VM with fresh data while keeping the initial node/name/status
            self.vm = ProxmoxVM(
                vmid: initialVM.vmid,
                name: initialVM.name,
                node: initialVM.node,
                status: initialVM.status,
                cpus: detail.cpus,
                maxmem: detail.maxmem,
                mem: detail.mem,
                uptime: detail.uptime,
                netin: detail.netin,
                netout: detail.netout
            )
            NSLog("✅ VM detail refreshed for VM %@", initialVM.vmid)
        } catch {
            NSLog("❌ Failed to refresh VM detail: %@", "\(error)")
            errorMessage = "Failed to refresh VM details: \(error.localizedDescription)"
        }

        isLoading = false
        NSLog("🔄 VMDetailViewModel.refresh() completed for VM %@", initialVM.vmid)
    }
}
