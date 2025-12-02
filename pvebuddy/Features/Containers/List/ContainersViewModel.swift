import Foundation
import SwiftUI
import Combine

@MainActor
final class ContainersViewModel: ObservableObject {
    @Published var containers: [ProxmoxContainer] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var nodes: [String] = []
    @Published var selectedNode: String? = nil

    private let client: ProxmoxClient
    private var autoRefreshTask: Task<Void, Never>?

    init(serverAddress: String) {
        self.client = ProxmoxClient(baseAddress: serverAddress)
    }

    deinit { autoRefreshTask?.cancel() }

    func startAutoRefresh() {
        autoRefreshTask?.cancel()
        autoRefreshTask = Task {
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
            let fetched = try await client.fetchAllContainers()
            if let node = selectedNode, !node.isEmpty {
                containers = fetched.filter { $0.node == node }
            } else {
                containers = fetched
            }
        } catch let error as ProxmoxClientError {
            switch error {
            case .invalidURL:
                errorMessage = "Invalid server address."
            case .requestFailed(let code, _):
                errorMessage = "Server error (HTTP \(code))."
            case .decodingFailed:
                errorMessage = "Unexpected response format."
            case .noNodesFound:
                errorMessage = "No containers found."
            }
        } catch {
            errorMessage = "Unexpected error: \(error.localizedDescription)"
        }
        isLoading = false
    }

    func loadNodes() async {
        do {
            nodes = try await client.fetchAllNodeNames()
        } catch {
            nodes = []
        }
    }
}
