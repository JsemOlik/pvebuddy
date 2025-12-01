import Foundation
import SwiftUI
import Combine

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published var status: ProxmoxNodeStatus?
    @Published var storages: [ProxmoxStorage] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    // Node selection state
    @Published var nodeNames: [String] = []
    @Published var selectedNode: String? = nil
    @Published var isDatacenter: Bool = false

    // Time series samples (circular buffer)
    struct Sample: Identifiable {
        let id = UUID()
        let date: Date
        let cpuPercent: Double // 0-100
        let memUsed: Int64
        let memTotal: Int64
    }

    @Published var samples: [Sample] = []
    private let maxSamples = 300 // keep ~15 minutes at 3s interval

    private let client: ProxmoxClient
    private var autoRefreshTask: Task<Void, Never>?

    init(serverAddress: String) {
        self.client = ProxmoxClient(baseAddress: serverAddress)
        Task { await fetchNodeNames() }
    }

    deinit {
        autoRefreshTask?.cancel()
    }

    func startAutoRefresh() {
        autoRefreshTask?.cancel()
        autoRefreshTask = Task {
            while !Task.isCancelled {
                await refresh()
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    func stopAutoRefresh() {
        autoRefreshTask?.cancel()
        autoRefreshTask = nil
    }

    func fetchNodeNames() async {
        do {
            let names = try await client.fetchAllNodeNames()
            DispatchQueue.main.async {
                self.nodeNames = names
                // Default to first node if none selected
                if self.selectedNode == nil && !names.isEmpty {
                    self.selectedNode = names.first
                }
            }
        } catch {
            print("❌ Failed to fetch node names: \(error)")
        }
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil

        do {
            if isDatacenter {
                let statusValue = try await client.fetchAllStatus()
                status = statusValue
                storages = []
            } else if let node = selectedNode {
                async let statusResult = client.fetchStatus(for: node)
                async let storageResult = client.fetchStorages(for: node)
                let (statusValue, storageValue) = try await (statusResult, storageResult)
                status = statusValue
                storages = storageValue
            } else {
                throw ProxmoxClientError.noNodesFound
            }
            // Append a time series sample if we have status
            if let s = status {
                let sample = Sample(date: Date(), cpuPercent: max(0, min(100, s.cpu * 100.0)), memUsed: s.mem, memTotal: s.maxmem)
                samples.append(sample)
                if samples.count > maxSamples {
                    samples.removeFirst(samples.count - maxSamples)
                }
            }
        } catch let error as ProxmoxClientError {
            switch error {
            case .invalidURL:
                errorMessage = "The server address looks invalid. Make sure it includes the scheme, e.g. https://pve.example.com:8006."
            case .requestFailed(let statusCode, _):
                if statusCode == 401 || statusCode == 403 {
                    errorMessage = "Authentication failed. Please double-check your API token ID and secret, and that the token has permissions."
                } else if statusCode == 0 || statusCode == -1 {
                    errorMessage = "Unable to reach your Proxmox server. Check the address, network, and HTTPS certificate (self-signed certs may need extra setup)."
                } else {
                    errorMessage = "Server returned an error (HTTP \(statusCode)). See the Xcode console for details."
                }
            case .decodingFailed:
                errorMessage = "Received data in an unexpected format. Make sure your Proxmox version is supported."
            case .noNodesFound:
                errorMessage = "No nodes were returned by the Proxmox API. Check that your token has permission to view the cluster."
            }
        } catch {
            errorMessage = "Unexpected error: \(error.localizedDescription)"
        }

        isLoading = false
    }
}
