import SwiftUI

struct VMsView: View {
    @AppStorage("pve_server_address") private var storedServerAddress: String = ""
    @StateObject private var viewModel: VMsViewModel
    @State private var selectedProxmoxVM: ProxmoxVM? = nil
    @State private var pickerSelection: String = "Datacenter"

    init() {
        let address = UserDefaults.standard.string(forKey: "pve_server_address") ?? ""
        _viewModel = StateObject(wrappedValue: VMsViewModel(serverAddress: address))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                if let selected = selectedProxmoxVM {
                    VMDetailView(vm: selected, onBack: { selectedProxmoxVM = nil })
                } else if viewModel.isLoading && viewModel.vms.isEmpty {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Loading VMs…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } else if let message = viewModel.errorMessage {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Unable to load VMs", systemImage: "exclamationmark.triangle.fill")
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
                    .padding(20)
                } else if viewModel.vms.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("No VMs found")
                            .font(.subheadline.weight(.semibold))

                        Text("Pull down to refresh or check that you have permissions to view VMs.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            header

                            // Node selector: allow filtering VMs by node. "Datacenter" == all nodes.
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Node")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.secondary)

                                    Spacer()
                                }

                                let pickerItems = (["Datacenter"] + viewModel.nodes)

                                Picker("Node", selection: $pickerSelection) {
                                    ForEach(pickerItems, id: \.self) { item in
                                        Text(item).tag(item)
                                    }
                                }
                                .pickerStyle(.menu)
                                .onChange(of: pickerSelection) { new in
                                    // Map "Datacenter" -> nil
                                    viewModel.selectedNode = (new == "Datacenter") ? nil : new
                                    Task { await viewModel.refresh() }
                                }
                                .onAppear {
                                    // ensure initial mapping
                                    viewModel.selectedNode = nil
                                }
                            }

                            VStack(spacing: 12) {
                                ForEach(viewModel.vms) { vm in
                                    Button(action: { selectedProxmoxVM = vm }) {
                                        vmCard(vm)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 24)
                    }
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Menu {
                                Button {
                                    // TODO: implement bulk start action
                                } label: {
                                    Label("Bulk Start", systemImage: "play.fill")
                                }

                                Button {
                                    // TODO: implement bulk shutdown action
                                } label: {
                                    Label("Bulk Shutdown", systemImage: "power")
                                }

                                Button {
                                    // TODO: implement bulk suspend action
                                } label: {
                                    Label("Bulk Suspend", systemImage: "pause.fill")
                                }
                            } label: {
                                Image(systemName: "square.grid.2x2")
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Bulk Actions")
                        }
                    }
                    .navigationTitle("VMs")
                    .navigationBarTitleDisplayMode(.large)
                    .navigationBarBackButtonHidden(true)
                    .onAppear {
                        viewModel.startAutoRefresh()
                        Task { await viewModel.refresh() }
                    }
                    .onDisappear {
                        viewModel.stopAutoRefresh()
                    }
                    .refreshable {
                        await viewModel.refresh()
                    }
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.purple.opacity(0.6), Color.blue.opacity(0.6)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 26, height: 26)
                    .overlay(
                        Image(systemName: "cube.transparent")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text("Virtual Machines")
                        .font(.title2.bold())

                    Text("Manage your VMs and containers.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func vmCard(_ vm: ProxmoxVM) -> some View {
        let memUsedGB = Double(vm.mem) / 1024.0 / 1024.0 / 1024.0
        let memMaxGB = Double(vm.maxmem) / 1024.0 / 1024.0 / 1024.0
        
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(vm.name)
                        .font(.subheadline.weight(.semibold))

                    Text(vm.node)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                statusBadge(vm.status)
            }

            HStack(spacing: 16) {
                HStack(spacing: 6) {
                    Image(systemName: "cpu")
                        .font(.caption)
                        .foregroundStyle(.blue)
                    Text("0/\(vm.cpus) cores")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 6) {
                    Image(systemName: "memorychip")
                        .font(.caption)
                        .foregroundStyle(.green)
                    Text(String(format: "%.1f/%.0f GB", memUsedGB, memMaxGB))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color(.separator).opacity(0.4), lineWidth: 0.5)
        )
    }

    private func statusBadge(_ status: String) -> some View {
        let (bgColor, textColor, icon) = statusColors(status)
        return HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
            Text(status.capitalized)
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(textColor)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(bgColor.opacity(0.15))
        .cornerRadius(6)
    }

    private func statusColors(_ status: String) -> (Color, Color, String) {
        switch status.lowercased() {
        case "running":
            return (.green, .green, "play.circle.fill")
        case "stopped":
            return (.red, .red, "stop.circle.fill")
        case "suspended":
            return (.orange, .orange, "pause.circle.fill")
        default:
            return (.gray, .gray, "questionmark.circle.fill")
        }
    }
}

// MARK: - VM Detail View

struct VMDetailView: View {
    let vm: ProxmoxVM
    let onBack: () -> Void
    
    @State private var showShutdownConfirm: Bool = false
    @State private var showRebootConfirm: Bool = false
    @State private var showStartConfirm: Bool = false

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header

                    usageMetricsGrid

                    controlButtonsSection
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
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
        .alert("Shut down VM?", isPresented: $showShutdownConfirm) {
            Button("Shut Down", role: .destructive) {
                // TODO: implement shutdown
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Are you sure you want to shut down \(vm.name)?")
        }
        .alert("Reboot VM?", isPresented: $showRebootConfirm) {
            Button("Reboot", role: .destructive) {
                // TODO: implement reboot
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Are you sure you want to reboot \(vm.name)?")
        }
        .alert("Start VM?", isPresented: $showStartConfirm) {
            Button("Start", role: .none) {
                // TODO: implement start
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Are you sure you want to start \(vm.name)?")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(vm.name)
                .font(.title2.bold())

            HStack(spacing: 12) {
                statusBadge(vm.status)
                Text(vm.node)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var usageMetricsGrid: some View {
        let memUsedGB = Double(vm.mem) / 1024.0 / 1024.0 / 1024.0
        let memMaxGB = Double(vm.maxmem) / 1024.0 / 1024.0 / 1024.0
        
        return VStack(spacing: 16) {
            HStack(spacing: 16) {
                metricCard(
                    title: "CPU Usage",
                    value: "0/\(vm.cpus) cores",
                    accentColor: .blue,
                    systemImage: "cpu"
                )

                metricCard(
                    title: "RAM Usage",
                    value: String(format: "%.1f/%.0f GB", memUsedGB, memMaxGB),
                    accentColor: .green,
                    systemImage: "memorychip"
                )
            }
        }
    }

    private func metricCard(
        title: String,
        value: String,
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
                Text(value)
                    .font(.system(size: 20, weight: .bold, design: .rounded))

                Spacer()
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color(.separator).opacity(0.4), lineWidth: 0.5)
        )
    }

    private var controlButtonsSection: some View {
        HStack(spacing: 12) {
            // Shutdown button (red)
            Button(action: { showShutdownConfirm = true }) {
                ZStack {
                    Circle().fill(Color.red)
                    Image(systemName: "power")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 50, height: 50)
            }
            .buttonStyle(.plain)

            // Reboot button (yellow)
            Button(action: { showRebootConfirm = true }) {
                ZStack {
                    Circle().fill(Color.yellow)
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.black)
                }
                .frame(width: 50, height: 50)
            }
            .buttonStyle(.plain)

            // Console button (blue pill)
            Button(action: {
                // TODO: implement console action
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "terminal")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Console")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.blue)
                .cornerRadius(25)
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .padding(.top, 12)
    }

    private func statusBadge(_ status: String) -> some View {
        let (bgColor, textColor, icon) = statusColors(status)
        return HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
            Text(status.capitalized)
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(textColor)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(bgColor.opacity(0.15))
        .cornerRadius(6)
    }

    private func statusColors(_ status: String) -> (Color, Color, String) {
        switch status.lowercased() {
        case "running":
            return (.green, .green, "play.circle.fill")
        case "stopped":
            return (.red, .red, "stop.circle.fill")
        case "suspended":
            return (.orange, .orange, "pause.circle.fill")
        default:
            return (.gray, .gray, "questionmark.circle.fill")
        }
    }
}

#Preview {
    VMsView()
}
