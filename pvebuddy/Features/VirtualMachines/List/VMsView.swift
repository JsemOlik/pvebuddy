//
//  VMsView.swift
//  pvebuddy
//
//  Created by Oliver Steiner on 01.12.2025.
//

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
        Color(.systemGroupedBackground).ignoresSafeArea()

        if let selected = selectedProxmoxVM {
          VmDetailView(
            vm: selected,
            serverAddress: storedServerAddress,
            onBack: { selectedProxmoxVM = nil }
          )
        } else if viewModel.isLoading && viewModel.vms.isEmpty {
          ScrollView {
            VStack(spacing: 12) {
              ProgressView()
              Text("Loading VMs…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            .frame(maxHeight: .infinity, alignment: .center)
          }
        } else if let message = viewModel.errorMessage {
          ScrollView {
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
          }
        } else if viewModel.vms.isEmpty {
          ScrollView {
            VStack(alignment: .leading, spacing: 8) {
              Text("No VMs found")
                .font(.subheadline.weight(.semibold))
              Text("Pull down to refresh or check that you have permissions to view VMs.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
          }
        } else {
          ScrollView {
            VStack(alignment: .leading, spacing: 24) {
              header

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
                // iOS 17+ preferred onChange overload
                .onChange(of: pickerSelection) { _, new in
                  viewModel.selectedNode = (new == "Datacenter") ? nil : new
                  Task { await viewModel.refresh() }
                }
                .onAppear {
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
                Button { } label: {
                  Label("Bulk Start", systemImage: "play.fill")
                }
                Button { } label: {
                  Label("Bulk Shutdown", systemImage: "power")
                }
                Button { } label: {
                  Label("Bulk Suspend", systemImage: "pause.fill")
                }
              } label: {
                Image(systemName: "square.grid.2x2")
              }
              .buttonStyle(.plain)
              .accessibilityLabel("Bulk Actions")
            }
          }
        }
      }
      .navigationTitle("VMs")
      .navigationBarTitleDisplayMode(.large)
      .navigationBarBackButtonHidden(true)
      .onAppear {
        viewModel.startAutoRefresh()
        Task { await viewModel.refresh() }
      }
      .onDisappear { viewModel.stopAutoRefresh() }
      .refreshable {
        if selectedProxmoxVM == nil {
          await viewModel.refresh()
        }
      }
      .onChange(of: selectedProxmoxVM) { _, new in
        if new != nil {
          viewModel.stopAutoRefresh()
        } else {
          viewModel.startAutoRefresh()
          Task { await viewModel.refresh() }
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
          Text("Virtual Machines").font(.title2.bold())
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
      HStack(alignment: .center, spacing: 10) {
        if let imageName = distroImageName(from: vm.tags) {
          Image(imageName)
            .resizable()
            .scaledToFill()
            .frame(width: 28, height: 28)
            .clipShape(Circle())
        }

        VStack(alignment: .leading, spacing: 4) {
          Text(vm.name).font(.subheadline.weight(.semibold))
          Text(vm.node).font(.caption).foregroundStyle(.secondary)
        }
        Spacer()
        statusBadge(vm.status)
      }

      HStack(spacing: 16) {
        HStack(spacing: 6) {
          Image(systemName: "cpu").font(.caption).foregroundStyle(.blue)
          Text("0/\(vm.cpus) cores")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        HStack(spacing: 6) {
          Image(systemName: "memorychip").font(.caption).foregroundStyle(.green)
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
      Image(systemName: icon).font(.caption.weight(.semibold))
      Text(status.capitalized).font(.caption.weight(.semibold))
    }
    .foregroundStyle(textColor)
    .padding(.horizontal, 10)
    .padding(.vertical, 6)
    .background(bgColor.opacity(0.15))
    .cornerRadius(6)
  }

  private func statusColors(_ status: String) -> (Color, Color, String) {
    switch status.lowercased() {
    case "running": return (.green, .green, "play.circle.fill")
    case "stopped": return (.red, .red, "stop.circle.fill")
    case "suspended", "paused": return (.orange, .orange, "pause.circle.fill")
    default: return (.gray, .gray, "questionmark.circle.fill")
    }
  }

  private func distroImageName(from tags: String?) -> String? {
    guard let tags, !tags.isEmpty else { return nil }
    let parts = tags
      .split(separator: ",")
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
    for p in parts {
      if p.contains("ubuntu") { return "distro_ubuntu" }
      if p.contains("debian") { return "distro_debian" }
      if p.contains("arch") { return "distro_arch" }
      if p.contains("fedora") { return "distro_fedora" }
      if p.contains("nixos") || p.contains("nix os") { return "distro_nixos" }
      if p.contains("centos") { return "distro_centos" }
      if p.contains("rocky") { return "distro_rocky" }
      if p.contains("alma") { return "distro_alma" }
      if p.contains("opensuse") || p.contains("open suse") || p.contains("suse") { return "distro_opensuse" }
      if p.contains("kali") { return "distro_kali" }
      if p.contains("pop") { return "distro_popos" }
      if p.contains("mint") { return "distro_mint" }
      if p.contains("manjaro") { return "distro_manjaro" }
      if p.contains("gentoo") { return "distro_gentoo" }
      if p.contains("alpine") { return "distro_alpine" }
      if p.contains("rhel") || p.contains("redhat") || p.contains("red hat") { return "distro_rhel" }
      if p.contains("oracle") { return "distro_oracle" }
      if p.contains("freebsd") { return "distro_freebsd" }
      if p.contains("windows") || p.contains("win11") || p.contains("win10") { return "distro_windows" }
    }
    return nil
  }
}
