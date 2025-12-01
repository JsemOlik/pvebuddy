import SwiftUI
import Combine

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published var status: ProxmoxNodeStatus?
    @Published var storages: [ProxmoxStorage] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

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

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil

        do {
            async let statusResult = client.fetchOverallStatus()
            async let storageResult = client.fetchStoragesForNode()

            let (statusValue, storageValue) = try await (statusResult, storageResult)
            status = statusValue
            storages = storageValue
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

struct DashboardView: View {
    @StateObject private var viewModel: DashboardViewModel
    @State private var showRebootConfirm: Bool = false
    @State private var showShutdownConfirm: Bool = false

    init(serverAddress: String) {
        _viewModel = StateObject(wrappedValue: DashboardViewModel(serverAddress: serverAddress))
    }

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header

                    if let status = viewModel.status {
                        statsGrid(for: status)
                    } else if viewModel.isLoading {
                        loadingState
                    } else if let message = viewModel.errorMessage {
                        errorState(message: message)
                    } else {
                        emptyState
                    }

                    if !viewModel.storages.isEmpty {
                        storageSection
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
            }
        }
        .navigationTitle("Dashboard")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        showRebootConfirm = true
                    } label: {
                        HStack {
                            Image(systemName: "arrow.clockwise")
                                .foregroundStyle(.blue)
                            Text("Reboot")
                        }
                    }

                    Button {
                        showShutdownConfirm = true
                    } label: {
                        HStack {
                            Image(systemName: "power")
                                .foregroundStyle(.blue)
                            Text("Shutdown")
                        }
                    }
                } label: {
                    ZStack {
                        Circle().fill(Color.red)
                        Image(systemName: "power")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 36, height: 36)
                    .contentShape(Circle())
                }
                .menuIndicator(.hidden)
                .buttonStyle(.plain)
                .accessibilityLabel("Power")
            }
        }
        .navigationBarBackButtonHidden(true)
        .onAppear {
            viewModel.startAutoRefresh()
        }
        .onDisappear {
            viewModel.stopAutoRefresh()
        }
        .refreshable {
            await viewModel.refresh()
        }
        .alert("Reboot node?", isPresented: $showRebootConfirm) {
            Button("Reboot", role: .destructive) {
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Are you sure you want to reboot this node?")
        }
        .alert("Shut down node?", isPresented: $showShutdownConfirm) {
            Button("Shut Down", role: .destructive) {
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Are you sure you want to shut down this node?")
        }
    }

    // MARK: - Subviews

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.blue.opacity(0.6), Color.green.opacity(0.6)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 26, height: 26)
                    .overlay(
                        Image(systemName: "server.rack")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text("Cluster overview")
                        .font(.title2.bold())

                    Text("Live health of your Proxmox node.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func statsGrid(for status: ProxmoxNodeStatus) -> some View {
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                usageCard(
                    title: "CPU usage",
                    value: cpuPercentage(from: status),
                    accentColor: .blue,
                    systemImage: "cpu"
                )

                usageCard(
                    title: "Memory usage",
                    value: memoryPercentage(from: status),
                    accentColor: .green,
                    systemImage: "memorychip"
                )
            }

            HStack(spacing: 16) {
                usageCard(
                    title: "Swap usage",
                    value: swapPercentage(from: status),
                    accentColor: .purple,
                    systemImage: "arrow.triangle.2.circlepath.circle"
                )

                usageCard(
                    title: "I/O delay",
                    value: ioDelayPercentage(from: status),
                    accentColor: .orange,
                    systemImage: "slowmo"
                )
            }
        }
    }

    private var storageSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Storage")
                .font(.headline.weight(.semibold))

            Text("All storage devices on this node, ordered by how little free space is left.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            let sortedStorages = viewModel.storages.sorted { $0.avail < $1.avail }

            VStack(spacing: 12) {
                ForEach(sortedStorages) { storage in
                    storageCard(storage)
                }
            }
        }
    }

    private func storageCard(_ storage: ProxmoxStorage) -> some View {
        let used = Double(storage.used)
        let total = Double(storage.total)
        let percentage = total > 0 ? max(0, min(100, (used / total) * 100.0)) : 0
        let freeBytes = storage.avail

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(storage.storage)
                        .font(.subheadline.weight(.semibold))

                    Text(storage.type.uppercased())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text("\(Int(percentage))%")
                    .font(.subheadline.weight(.semibold))
            }

            ProgressView(value: percentage / 100.0)
                .tint(.blue)
                .progressViewStyle(.linear)

            Text("\(formatBytes(storage.used)) used of \(formatBytes(storage.total)) • \(formatBytes(freeBytes)) free")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(.systemBackground),
                            Color(.secondarySystemBackground)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color(.separator).opacity(0.4), lineWidth: 0.5)
        )
    }

    private func usageCard(
        title: String,
        value: Double,
        accentColor: Color,
        systemImage: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: systemImage)
                    .imageScale(.medium)
                    .foregroundStyle(accentColor)
                    .frame(width: 24, height: 24)

                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()
            }

            HStack(alignment: .lastTextBaseline) {
                Text("\(Int(value))%")
                    .font(.system(size: 28, weight: .bold, design: .rounded))

                Spacer()
            }

            ProgressView(value: value / 100.0)
                .tint(accentColor)
                .progressViewStyle(.linear)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color(.separator).opacity(0.5), lineWidth: 0.5)
        )
    }

    private var loadingState: some View {
        VStack(alignment: .center, spacing: 12) {
            ProgressView()
            Text("Loading metrics…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 32)
    }

    private func errorState(message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Unable to load metrics", systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)

            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.3), lineWidth: 0.5)
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 24)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No data yet")
                .font(.subheadline.weight(.semibold))

            Text("Pull down to refresh and load the latest metrics from your Proxmox server.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 24)
    }

    // MARK: - Formatting helpers

    private func cpuPercentage(from status: ProxmoxNodeStatus) -> Double {
        max(0, min(100, status.cpu * 100.0))
    }

    private func memoryPercentage(from status: ProxmoxNodeStatus) -> Double {
        guard status.maxmem > 0 else { return 0 }
        return max(0, min(100, (Double(status.mem) / Double(status.maxmem)) * 100.0))
    }

    private func swapPercentage(from status: ProxmoxNodeStatus) -> Double {
        guard status.maxswap > 0 else { return 0 }
        return max(0, min(100, (Double(status.swap) / Double(status.maxswap)) * 100.0))
    }

    private func ioDelayPercentage(from status: ProxmoxNodeStatus) -> Double {
        // `wait` is already normalized to percent in the model.
        return max(0, min(100, status.wait))
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useTB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

#Preview {
    NavigationStack {
        DashboardView(serverAddress: "https://pve.example.com:8006")
    }
}
