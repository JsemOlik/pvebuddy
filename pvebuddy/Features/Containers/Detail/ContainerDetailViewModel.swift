//
//  ContainerDetailViewModel.swift
//  pvebuddy
//
//  Created by Oliver Steiner on 01.12.2025.
//

import Foundation
import SwiftUI
import Combine

@MainActor
final class ContainerDetailViewModel: ObservableObject {
  @Published var container: ProxmoxContainer
  @Published var isLoading: Bool = false
  @Published var errorMessage: String?
  @Published var isActing: Bool = false

  @Published var liveStatus: String = "unknown"
  @Published var cpuPercent: Double = 0.0
  @Published var memUsed: Int64 = 0
  @Published var memMax: Int64 = 0
  @Published var displayedUptime: Int64 = 0

  struct ChartPoint: Identifiable {
    let id = UUID()
    let date: Date
    let cpuPercent: Double
    let memUsedBytes: Int64
    let memTotalBytes: Int64
  }
  @Published var chartPoints: [ChartPoint] = []
  private let maxChartSeconds: TimeInterval = 120

  @Published var nodeStatus: ProxmoxNodeStatus?

  @Published var hardware: [HardwareSection] = []
  @Published var hardwareLoading: Bool = false
  @Published var hardwareError: String?
  @Published var rawConfig: [String: String] = [:]

  struct HardwareItem: Identifiable { let id = UUID(); let key: String; let value: String }
  struct HardwareSection: Identifiable { let id = UUID(); let title: String; let items: [HardwareItem] }

  private let client: ProxmoxClient
  private let initialContainer: ProxmoxContainer
  private var autoRefreshTask: Task<Void, Never>?
  private var detailRefreshTick: Int = 0

  init(container: ProxmoxContainer, serverAddress: String) {
    self.initialContainer = container
    self.container = container
    self.client = ProxmoxClient(baseAddress: serverAddress)
    self.liveStatus = container.status
    self.memUsed = container.mem
    self.memMax = container.maxmem
    self.displayedUptime = container.uptime ?? 0
  }

  deinit { autoRefreshTask?.cancel() }

  func startAutoRefresh() {
    autoRefreshTask?.cancel()
    autoRefreshTask = Task { [weak self] in
      guard let self else { return }
      await self.backfillContainerChart()
      await self.loadNodeStatus()
      while !Task.isCancelled {
        await self.refreshLive()
        if self.liveStatus.lowercased() == "running" {
          withAnimation(.linear(duration: 0.2)) {
            self.displayedUptime += 1
          }
        }
        self.detailRefreshTick += 1
        if self.detailRefreshTick % 3 == 0 {
          await self.refreshDetails()
        }
        if self.detailRefreshTick % 10 == 0 {
          await self.loadNodeStatus()
        }
        try? await Task.sleep(nanoseconds: 1_000_000_000)
      }
    }
  }

  func stopAutoRefresh() {
    autoRefreshTask?.cancel()
    autoRefreshTask = nil
  }

  func refresh() async {
    await refreshDetails()
    await refreshLive()
    await loadNodeStatus()
  }

  // expose live node refresh for EditContainerResourcesSheet ticker
  func loadNodeStatus() async {
    do {
      self.nodeStatus = try await client.fetchStatus(for: initialContainer.node)
    } catch { }
  }

  private func trimChart() {
    let cutoff = Date().addingTimeInterval(-maxChartSeconds)
    chartPoints.removeAll { $0.date < cutoff }
  }

  private func appendLivePoint() {
    let point = ChartPoint(
      date: Date(),
      cpuPercent: max(0, min(100, cpuPercent)),
      memUsedBytes: memUsed,
      memTotalBytes: memMax
    )
    chartPoints.append(point)
    trimChart()
  }

  private func backfillContainerChart() async {
    do {
      let entries = try await client.fetchLXCRRD(
        node: initialContainer.node,
        vmid: initialContainer.vmid,
        timeframe: "hour",
        cf: "AVERAGE"
      )
      let now = Date()
      let cutoff = now.addingTimeInterval(-maxChartSeconds)
      let filtered = entries.filter { Date(timeIntervalSince1970: TimeInterval($0.time)) >= cutoff }
      var pts: [ChartPoint] = []
      for e in filtered {
        let d = Date(timeIntervalSince1970: TimeInterval(e.time))
        let cpuPct = max(0.0, min(100.0, (e.cpu ?? 0.0) * 100.0))
        let usedBytes = Int64(e.mem ?? 0.0)
        let totalBytes = Int64(e.maxmem ?? Double(self.memMax))
        pts.append(ChartPoint(date: d, cpuPercent: cpuPct, memUsedBytes: usedBytes, memTotalBytes: totalBytes))
      }
      self.chartPoints = pts.sorted { $0.date < $1.date }
      trimChart()
    } catch { }
  }

  private func refreshDetails() async {
    guard !isLoading else { return }
    isLoading = true
    defer { isLoading = false }
    do {
      let detail = try await self.client.fetchLXCDetail(
        node: self.initialContainer.node,
        vmid: self.initialContainer.vmid
      )
      self.container = ProxmoxContainer(
        vmid: self.initialContainer.vmid,
        name: self.initialContainer.name,
        node: self.initialContainer.node,
        status: self.liveStatus,
        cpus: detail.cpus,
        maxmem: detail.maxmem,
        mem: detail.mem,
        uptime: detail.uptime,
        netin: detail.netin,
        netout: detail.netout,
        tags: self.container.tags
      )
      self.memMax = detail.maxmem
      self.memUsed = detail.mem
      if let up = detail.uptime { self.displayedUptime = up }
    } catch {
      self.errorMessage = "Failed to refresh Container details: \(error.localizedDescription)"
    }
  }

  private func refreshLive() async {
    do {
      let s = try await self.client.fetchLXCCurrentStatus(
        node: self.initialContainer.node,
        vmid: self.initialContainer.vmid
      )
      self.liveStatus = s.status
      self.cpuPercent = max(0, min(100, s.cpuFraction * 100.0))
      if s.memMax > 0 {
        self.memUsed = s.memUsed
        self.memMax = s.memMax
      }
      self.container = ProxmoxContainer(
        vmid: self.container.vmid,
        name: self.container.name,
        node: self.container.node,
        status: self.liveStatus,
        cpus: self.container.cpus,
        maxmem: self.container.maxmem,
        mem: self.memUsed,
        uptime: self.container.uptime,
        netin: self.container.netin,
        netout: self.container.netout,
        tags: self.container.tags
      )
      appendLivePoint()
    } catch { }
  }

  func shutdown(forceOnFailure: Bool = false) async {
    await withActionState { [weak self] in
      guard let self else { return }
      try await self.client.shutdownLXC(
        node: self.initialContainer.node,
        vmid: self.initialContainer.vmid,
        force: forceOnFailure,
        timeout: 60
      )
      await self.refresh()
    }
  }

  func reboot() async {
    await withActionState { [weak self] in
      guard let self else { return }
      try await self.client.rebootLXC(node: self.initialContainer.node, vmid: self.initialContainer.vmid)
      await self.refresh()
    }
  }

  func start() async {
    await withActionState { [weak self] in
      guard let self else { return }
      try await self.client.startLXC(node: self.initialContainer.node, vmid: self.initialContainer.vmid)
      await self.refresh()
    }
  }

  func forceStop() async {
    await withActionState { [weak self] in
      guard let self else { return }
      try await self.client.stopLXC(node: self.initialContainer.node, vmid: self.initialContainer.vmid)
      await self.refresh()
    }
  }

  private func withActionState(_ work: @escaping () async throws -> Void) async {
    self.isActing = true
    self.errorMessage = nil
    defer { self.isActing = false }
    do {
      try await work()
    } catch let e as ProxmoxClientError {
      switch e {
      case .requestFailed(let code, let message):
        self.errorMessage = "Action failed (HTTP \(code)): \(message)"
      case .invalidURL:
        self.errorMessage = "Invalid server URL."
      case .decodingFailed(let underlying):
        self.errorMessage = "Decoding failed: \(underlying.localizedDescription)"
      case .noNodesFound:
        self.errorMessage = "No nodes found."
      }
    } catch {
      self.errorMessage = "Unexpected error: \(error.localizedDescription)"
    }
  }

  func loadHardware() async {
    guard !hardwareLoading else { return }
    hardwareLoading = true
    hardwareError = nil
    defer { hardwareLoading = false }

    do {
      let cfg = try await self.client.fetchLXCConfig(
        node: self.initialContainer.node,
        vmid: self.initialContainer.vmid
      )
      self.rawConfig = cfg
      self.hardware = Self.groupConfig(cfg)
    } catch {
      self.hardware = []
      self.rawConfig = [:]
      self.hardwareError = "Failed to load hardware: \(error.localizedDescription)"
    }
  }

  private static func groupConfig(_ cfg: [String: String]) -> [HardwareSection] {
    func items(_ pairs: [(String, String)]) -> [HardwareItem] { pairs.map { HardwareItem(key: $0.0, value: $0.1) } }
    var sections: [HardwareSection] = []

    // LXC-specific CPU & Memory keys (no sockets, balloon, machine, bios for LXC)
    let cpuMemKeys = ["cores","cpulimit","cpu","memory","swap"]
    let cpuMem = cpuMemKeys.compactMap { k in cfg[k].map { (k, $0) } }
    if !cpuMem.isEmpty { sections.append(HardwareSection(title: "CPU & Memory", items: items(cpuMem))) }

    let bootKeys = ["onboot", "startup"]
    let boot = bootKeys.compactMap { k in cfg[k].map { (k, $0) } }
    if !boot.isEmpty { sections.append(HardwareSection(title: "Boot", items: items(boot))) }

    // LXC uses rootfs, mp (mount points) instead of disk devices
    let storageKeys = ["rootfs", "mp", "mp0", "mp1", "mp2", "mp3", "mp4", "mp5", "mp6", "mp7", "mp8", "mp9"]
    let storagePairs = cfg.keys.filter { key in 
      storageKeys.contains(key) || key.hasPrefix("mp") || key.hasPrefix("rootfs")
    }.sorted().compactMap { k in cfg[k].map { (k, $0) } }
    if !storagePairs.isEmpty { sections.append(HardwareSection(title: "Storage", items: items(storagePairs))) }

    let netPairs = cfg.keys.filter { $0.hasPrefix("net") }.sorted().compactMap { k in cfg[k].map { (k, $0) } }
    if !netPairs.isEmpty { sections.append(HardwareSection(title: "Network", items: items(netPairs))) }

    // LXC-specific keys
    let lxcKeys = ["ostype", "arch", "hostname", "nameserver", "searchdomain", "unprivileged", "features"]
    let lxc = lxcKeys.compactMap { k in cfg[k].map { (k, $0) } }
    if !lxc.isEmpty { sections.append(HardwareSection(title: "LXC", items: items(lxc))) }

    let cloudKeys = ["cicustom","ciuser","cipassword","citype","ipconfig0","ipconfig1","ipconfig2","ipconfig3","ipconfig4","ipconfig5","ipconfig6","ipconfig7","ipconfig8","ipconfig9"]
    let cloud = cloudKeys.compactMap { k in cfg[k].map { (k, $0) } }
    if !cloud.isEmpty { sections.append(HardwareSection(title: "Cloud-Init", items: items(cloud))) }

    let usedKeys = Set(sections.flatMap { $0.items.map { $0.key } })
    let otherPairs = cfg.keys.filter { !usedKeys.contains($0) }.sorted().compactMap { k in cfg[k].map { (k, $0) } }
    if !otherPairs.isEmpty { sections.append(HardwareSection(title: "Other", items: items(otherPairs))) }

    return sections
  }

  func distroImageName(from tags: String?) -> String? {
    guard let tags, !tags.isEmpty else { return nil }
    let parts = tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
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

  // MARK: - Resource updates

  func updateResources(newCores: Int?, newMemoryMiB: Int?, newSwapMiB: Int?) async -> String? {
    await withActionState { [weak self] in
      guard let self else { return }
      try await self.client.updateLXCResources(
        node: self.initialContainer.node,
        vmid: self.initialContainer.vmid,
        cores: newCores,
        memoryMiB: newMemoryMiB,
        swapMiB: newSwapMiB
      )
      await self.refresh()
    }
    return self.errorMessage
  }
}
