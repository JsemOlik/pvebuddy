//
//  ContainerDetailView.swift
//  pvebuddy
//
//  Created by Oliver Steiner on 01.12.2025.
//

import SwiftUI
import Charts

struct ContainerDetailView: View {
    let initialContainer: ProxmoxContainer
    let serverAddress: String
    let onBack: () -> Void

    @StateObject private var viewModel: ContainerDetailViewModel
    @State private var showRebootConfirm: Bool = false
    @State private var showStartConfirm: Bool = false
    @State private var showShutdownConfirm: Bool = false
    @State private var showForceStopConfirm: Bool = false
    @State private var showHardware: Bool = false

    @State private var showConsole: Bool = false

    @State private var consoleCookies: [HTTPCookie]? = nil
    @State private var isPreparingConsole: Bool = false
    @State private var consoleError: String? = nil

    @State private var showEditResources = false

    init(container: ProxmoxContainer, serverAddress: String, onBack: @escaping () -> Void) {
        self.initialContainer = container
        self.serverAddress = serverAddress
        self.onBack = onBack
        _viewModel = StateObject(
            wrappedValue: ContainerDetailViewModel(container: container, serverAddress: serverAddress)
        )
    }

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    ContainerDetailHeader(
                        name: viewModel.container.name,
                        status: viewModel.liveStatus,
                        node: viewModel.container.node,
                        tags: viewModel.container.tags
                    )

                    ContainerMetricsGrid(
                        cpuPercent: viewModel.cpuPercent,
                        memUsedBytes: viewModel.memUsed,
                        memTotalBytes: viewModel.memMax,
                        containerCPUs: viewModel.container.cpus
                    )

                    ContainerUptimeCard(uptimeSeconds: viewModel.displayedUptime)

                    ContainerControlButtons(
                        onShutdown: { showShutdownConfirm = true },
                        onForceStop: { showForceStopConfirm = true },
                        onReboot: { showRebootConfirm = true },
                        onStart: { showStartConfirm = true },
                        onConsole: { Task { await openConsole() } },
                        onEditResources: { showEditResources = true }
                    )

                    ContainerHardwareSection(
                        isExpanded: $showHardware,
                        loading: viewModel.hardwareLoading,
                        error: viewModel.hardwareError,
                        hardware: viewModel.hardware,
                        onReload: { Task { await viewModel.loadHardware() } }
                    )

                    if let err = viewModel.errorMessage { errorBanner(err) }
                    if let cerr = consoleError { errorBanner("Console: \(cerr)") }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
            }

            if viewModel.isActing || isPreparingConsole {
                ProgressView()
                    .scaleEffect(1.2)
                    .padding()
                    .background(.ultraThinMaterial)
                    .cornerRadius(12)
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(action: onBack) {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Back")
                    }
                    .foregroundStyle(.blue)
                }
            }
        }
        .alert("Reboot Container?", isPresented: $showRebootConfirm) {
            Button("Reboot", role: .destructive) { Task { await viewModel.reboot() } }
            Button("Cancel", role: .cancel) { }
        } message: { Text("Reboot \(viewModel.container.name).") }
        .alert("Start Container?", isPresented: $showStartConfirm) {
            Button("Start") { Task { await viewModel.start() } }
            Button("Cancel", role: .cancel) { }
        } message: { Text("Start \(viewModel.container.name).") }
        .alert("Shut down Container?", isPresented: $showShutdownConfirm) {
            Button("Shut Down", role: .destructive) { Task { await viewModel.shutdown(forceOnFailure: false) } }
            Button("Cancel", role: .cancel) { }
        } message: { Text("Shut down \(viewModel.container.name).") }
        .alert("Force stop Container?", isPresented: $showForceStopConfirm) {
            Button("Force Stop", role: .destructive) { Task { await viewModel.forceStop() } }
            Button("Cancel", role: .cancel) { }
        } message: { Text("Immediately stop \(viewModel.container.name). Data loss possible.") }
        .sheet(isPresented: $showConsole) {
            if let consoleURL = consoleURL() {
                WebConsoleView(
                    url: consoleURL,
                    title: "\(viewModel.container.name) Console",
                    cookies: consoleCookies
                )
            }
        }
        .sheet(isPresented: $showEditResources) {
            EditContainerResourcesSheet(viewModel: viewModel)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .onAppear {
            viewModel.startAutoRefresh()
            Task {
                await viewModel.refresh()
                await viewModel.loadHardware()
            }
        }
        .onDisappear { viewModel.stopAutoRefresh() }
    }

    private func errorBanner(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Action error", systemImage: "exclamationmark.triangle.fill")
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
    }

    private func consoleURL() -> URL? {
        let base = serverAddress.hasSuffix("/") ? serverAddress : serverAddress + "/"
        let node = viewModel.container.node
        let vmid = viewModel.container.vmid
        var comps = URLComponents(string: base)
        comps?.queryItems = [
            .init(name: "console", value: "lxc"),
            .init(name: "node", value: node),
            .init(name: "novnc", value: "1"),
            .init(name: "vmid", value: vmid),
        ]
        return comps?.url
    }

    private func openConsole() async {
        consoleError = nil
        guard consoleURL() != nil else { return }
        isPreparingConsole = true
        defer { isPreparingConsole = false }

        let auth = WebAuthStore()
        guard auth.hasCreds else {
            consoleError = "No web credentials saved. Open Settings → Web Console Login."
            return
        }

        do {
            let client = ProxmoxClient(baseAddress: serverAddress)
            let (ticket, _) = try await client.loginForWebTicket(
                username: auth.username,
                password: auth.password,
                realm: auth.realm
            )
            guard let host = URL(string: serverAddress)?.host else {
                consoleError = "Invalid server address host."
                return
            }
            guard let cookie = makePVEAuthCookie(ticket: ticket, domain: host) else {
                consoleError = "Failed to create auth cookie."
                return
            }
            consoleCookies = [cookie]
            showConsole = true
        } catch {
            consoleError = "Login failed: \(error.localizedDescription)"
        }
    }

    private func makePVEAuthCookie(ticket: String, domain: String) -> HTTPCookie? {
        var props: [HTTPCookiePropertyKey: Any] = [
            .name: "PVEAuthCookie",
            .value: ticket,
            .domain: domain,
            .path: "/",
            .secure: true,
            .version: 0
        ]
        props[.expires] = Date().addingTimeInterval(60 * 30)
        return HTTPCookie(properties: props)
    }
}
