//
//  VMDetailView.swift
//  pvebuddy
//
//  Created by Oliver Steiner on 01.12.2025.
//

import SwiftUI

// This file defines only VMDetailView. The VMs list lives in VMsView.swift.

struct VMDetailView: View {
  let initialVM: ProxmoxVM
  let serverAddress: String
  let onBack: () -> Void

  @StateObject private var viewModel: VMDetailViewModel
  @State private var showRebootConfirm: Bool = false
  @State private var showStartConfirm: Bool = false
  @State private var showShutdownConfirm: Bool = false
  @State private var showForceStopConfirm: Bool = false
  @State private var showHardware: Bool = false

  @State private var showConsole: Bool = false

  // Console auth state
  @State private var consoleCookies: [HTTPCookie]? = nil
  @State private var isPreparingConsole: Bool = false
  @State private var consoleError: String? = nil

  init(vm: ProxmoxVM, serverAddress: String, onBack: @escaping () -> Void) {
    self.initialVM = vm
    self.serverAddress = serverAddress
    self.onBack = onBack
    _viewModel = StateObject(
      wrappedValue: VMDetailViewModel(vm: vm, serverAddress: serverAddress)
    )
  }

  var body: some View {
    ZStack {
      Color(.systemGroupedBackground).ignoresSafeArea()

      ScrollView {
        VStack(alignment: .leading, spacing: 24) {
          header
          usageMetricsGrid
          uptimeCard
          controlButtonsSection
          hardwareSection
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
    .alert("Reboot VM?", isPresented: $showRebootConfirm) {
      Button("Reboot", role: .destructive) { Task { await viewModel.reboot() } }
      Button("Cancel", role: .cancel) { }
    } message: { Text("Send ACPI reboot to \(viewModel.vm.name).") }
    .alert("Start VM?", isPresented: $showStartConfirm) {
      Button("Start") { Task { await viewModel.start() } }
      Button("Cancel", role: .cancel) { }
    } message: { Text("Start \(viewModel.vm.name).") }
    .alert("Shut down VM?", isPresented: $showShutdownConfirm) {
      Button("Shut Down", role: .destructive) { Task { await viewModel.shutdown(forceOnFailure: false) } }
      Button("Cancel", role: .cancel) { }
    } message: { Text("Send ACPI shutdown to \(viewModel.vm.name).") }
    .alert("Force stop VM?", isPresented: $showForceStopConfirm) {
      Button("Force Stop", role: .destructive) { Task { await viewModel.forceStop() } }
      Button("Cancel", role: .cancel) { }
    } message: { Text("Immediately power off \(viewModel.vm.name). Data loss possible.") }
    .sheet(isPresented: $showConsole) {
      if let consoleURL = consoleNoVNCURL() {
        WebConsoleView(
          url: consoleURL,
          title: "\(viewModel.vm.name) Console",
          cookies: consoleCookies
        )
      }
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

  // MARK: - Header

  private var header: some View {
    HStack(alignment: .center, spacing: 12) {
      if let imageName = viewModel.distroImageName(from: viewModel.vm.tags) {
        Image(imageName)
          .resizable()
          .scaledToFill()
          .frame(width: 36, height: 36)
          .clipShape(Circle())
      }
      VStack(alignment: .leading, spacing: 6) {
        Text(viewModel.vm.name).font(.title2.bold())
        HStack(spacing: 12) {
          statusBadge(viewModel.liveStatus)
          Text(viewModel.vm.node)
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
      }
      Spacer()
    }
  }

  // MARK: - Metrics

  private var usageMetricsGrid: some View {
    let memUsedGB = Double(viewModel.memUsed) / 1024.0 / 1024.0 / 1024.0
    let memMaxGB = Double(max(1, viewModel.memMax)) / 1024.0 / 1024.0 / 1024.0
    let memPct = viewModel.memMax > 0
      ? min(100.0, max(0.0, (Double(viewModel.memUsed) / Double(viewModel.memMax)) * 100.0))
      : 0

    return VStack(spacing: 16) {
      HStack(spacing: 16) {
        liveMetricCard(
          title: "CPU Usage",
          value: "\(Int(viewModel.cpuPercent))%",
          progress: viewModel.cpuPercent / 100.0,
          accentColor: .blue,
          systemImage: "cpu"
        )
        liveMetricCard(
          title: "RAM Usage",
          value: String(format: "%.1f/%.0f GB", memUsedGB, memMaxGB),
          progress: memPct / 100.0,
          accentColor: .green,
          systemImage: "memorychip"
        )
      }
    }
  }

  private func liveMetricCard(
    title: String,
    value: String,
    progress: Double,
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
        Text(value).font(.system(size: 20, weight: .bold, design: .rounded))
        Spacer()
      }
      ProgressView(value: min(max(progress, 0.0), 1.0))
        .tint(accentColor)
        .progressViewStyle(.linear)
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

  // MARK: - Uptime

  private var uptimeCard: some View {
    let text = formatUptime(viewModel.displayedUptime)
    return VStack(alignment: .leading, spacing: 8) {
      HStack {
        Image(systemName: "clock")
          .imageScale(.medium)
          .foregroundStyle(.purple)
          .frame(width: 24, height: 24)
        Text("Uptime")
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(.secondary)
        Spacer()
      }
      Text(text)
        .font(.system(size: 22, weight: .bold, design: .rounded))
        .monospacedDigit()
        .animation(.linear(duration: 0.2), value: text)
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

  private func formatUptime(_ seconds: Int64) -> String {
    let s = Int(seconds)
    let days = s / 86400
    let hrs = (s % 86400) / 3600
    let mins = (s % 3600) / 60
    let secs = s % 60
    if days > 0 {
      return "\(days)d \(String(format: "%02d:%02d:%02d", hrs, mins, secs))"
    } else {
      return String(format: "%02d:%02d:%02d", hrs, mins, secs)
    }
  }

  // MARK: - Controls

  private var controlButtonsSection: some View {
    HStack(spacing: 12) {
      Menu {
        Button(role: .destructive) {
          showShutdownConfirm = true
        } label: {
          HStack {
            Image(systemName: "power").foregroundStyle(.blue)
            Text("Shutdown").foregroundStyle(.primary)
          }
        }
        Button(role: .destructive) {
          showForceStopConfirm = true
        } label: {
          HStack {
            Image(systemName: "stop.fill").foregroundStyle(.blue)
            Text("Force Stop").foregroundStyle(.primary)
          }
        }
      } label: {
        ZStack {
          Circle().fill(Color.red)
          Image(systemName: "power")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
        }
        .frame(width: 50, height: 50)
      }
      .menuIndicator(.hidden)
      .buttonStyle(.plain)

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

      Button(action: { showStartConfirm = true }) {
        ZStack {
          Circle().fill(Color.green)
          Image(systemName: "play.fill")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
        }
        .frame(width: 50, height: 50)
      }
      .buttonStyle(.plain)

      Button(action: { Task { await openConsole() } }) {
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

  // MARK: - Hardware section

  private var hardwareSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      DisclosureGroup(isExpanded: $showHardware) {
        if viewModel.hardwareLoading {
          ProgressView().padding(.vertical, 8)
        } else if let err = viewModel.hardwareError {
          Text(err).font(.footnote).foregroundStyle(.secondary).padding(.vertical, 8)
        } else if viewModel.hardware.isEmpty {
          Text("No hardware information.").font(.footnote).foregroundStyle(.secondary).padding(.vertical, 8)
        } else {
          VStack(spacing: 12) {
            ForEach(viewModel.hardware) { section in
              VStack(alignment: .leading, spacing: 6) {
                Text(section.title).font(.subheadline.weight(.semibold))
                ForEach(section.items) { item in
                  HStack {
                    Text(item.key).font(.footnote).foregroundStyle(.secondary)
                    Spacer()
                    Text(item.value).font(.footnote)
                  }
                }
              }
              .padding(12)
              .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                  .fill(Color(.systemBackground))
              )
              .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                  .strokeBorder(Color(.separator).opacity(0.35), lineWidth: 0.5)
              )
            }
          }
          .padding(.top, 8)
        }
      } label: {
        HStack(spacing: 8) {
          Image(systemName: "wrench.and.screwdriver").foregroundStyle(.blue)
          Text("Hardware").font(.headline)
          Spacer()
          Button { Task { await viewModel.loadHardware() } } label: {
            Image(systemName: "arrow.clockwise").font(.subheadline).foregroundStyle(.secondary)
          }
          .buttonStyle(.plain)
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
  }

  // MARK: - Badges & banners

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
    case "paused", "suspended": return (.orange, .orange, "pause.circle.fill")
    default: return (.gray, .gray, "questionmark.circle.fill")
    }
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

  // MARK: - Console URL and auth

  // https://host/?console=kvm&node=NODE&novnc=1&vmid=VMID
  private func consoleNoVNCURL() -> URL? {
    let base = serverAddress.hasSuffix("/") ? serverAddress : serverAddress + "/"
    let node = viewModel.vm.node
    let vmid = viewModel.vm.vmid
    var comps = URLComponents(string: base)
    comps?.queryItems = [
      .init(name: "console", value: "kvm"),
      .init(name: "node", value: node),
      .init(name: "novnc", value: "1"),
      .init(name: "vmid", value: vmid),
    ]
    return comps?.url
  }

  private func openConsole() async {
    consoleError = nil
    guard consoleNoVNCURL() != nil else { return }
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
