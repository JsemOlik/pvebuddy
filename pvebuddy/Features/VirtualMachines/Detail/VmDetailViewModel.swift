//
//  VmDetailViewModel.swift
//  pvebuddy
//
//  Created by Oliver Steiner on 01.12.2025.
//

import Foundation
import SwiftUI
import Combine

@MainActor
final class VMDetailViewModel: ObservableObject {
  @Published var vm: ProxmoxVM
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
  private let maxChartSeconds: TimeInterval = 60 // Keep 1 minute of data for graphs

  @Published var nodeStatus: ProxmoxNodeStatus?

  @Published var hardware: [HardwareSection] = []
  @Published var hardwareLoading: Bool = false
  @Published var hardwareError: String?

  @Published var storages: [ProxmoxStorage] = []
  @Published var storagesLoading: Bool = false
  @Published var storagesError: String?

  struct VMDisk: Identifiable {
    let id: String
    let device: String // e.g., "scsi0", "sata0"
    let storage: String
    let size: Int64? // in bytes, if available
    let isBoot: Bool
    let rawValue: String
  }
  @Published var vmDisks: [VMDisk] = []

  struct HardwareItem: Identifiable { let id = UUID(); let key: String; let value: String }
  struct HardwareSection: Identifiable { let id = UUID(); let title: String; let items: [HardwareItem] }

  private let client: ProxmoxClient
  private let initialVM: ProxmoxVM
  private var autoRefreshTask: Task<Void, Never>?
  private var detailRefreshTick: Int = 0

  init(vm: ProxmoxVM, serverAddress: String) {
    self.initialVM = vm
    self.vm = vm
    self.client = ProxmoxClient(baseAddress: serverAddress)
    self.liveStatus = vm.status
    self.memUsed = vm.mem
    self.memMax = vm.maxmem
    self.displayedUptime = vm.uptime ?? 0
  }

  deinit { autoRefreshTask?.cancel() }

  func startAutoRefresh() {
    autoRefreshTask?.cancel()
    autoRefreshTask = Task { [weak self] in
      guard let self else { return }
      await self.backfillVMChart()
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

  // expose live node refresh for EditResourcesSheet ticker
  func loadNodeStatus() async {
    do {
      self.nodeStatus = try await client.fetchStatus(for: initialVM.node)
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

  private func backfillVMChart() async {
    do {
      let entries = try await client.fetchVMRRD(
        node: initialVM.node,
        vmid: initialVM.vmid,
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
      let detail = try await self.client.fetchVMDetail(
        node: self.initialVM.node,
        vmid: self.initialVM.vmid
      )
      self.vm = ProxmoxVM(
        vmid: self.initialVM.vmid,
        name: self.initialVM.name,
        node: self.initialVM.node,
        status: self.liveStatus,
        cpus: detail.cpus,
        maxmem: detail.maxmem,
        mem: detail.mem,
        uptime: detail.uptime,
        netin: detail.netin,
        netout: detail.netout,
        tags: self.vm.tags
      )
      self.memMax = detail.maxmem
      self.memUsed = detail.mem
      if let up = detail.uptime { self.displayedUptime = up }
    } catch {
      self.errorMessage = "Failed to refresh VM details: \(error.localizedDescription)"
    }
  }

  private func refreshLive() async {
    do {
      let s = try await self.client.fetchVMCurrentStatus(
        node: self.initialVM.node,
        vmid: self.initialVM.vmid
      )
      self.liveStatus = s.status
      self.cpuPercent = max(0, min(100, s.cpuFraction * 100.0))
      if s.memMax > 0 {
        self.memUsed = s.memUsed
        self.memMax = s.memMax
      }
      self.vm = ProxmoxVM(
        vmid: self.vm.vmid,
        name: self.vm.name,
        node: self.vm.node,
        status: self.liveStatus,
        cpus: self.vm.cpus,
        maxmem: self.vm.maxmem,
        mem: self.memUsed,
        uptime: self.vm.uptime,
        netin: self.vm.netin,
        netout: self.vm.netout,
        tags: self.vm.tags
      )
      appendLivePoint()
    } catch { }
  }

  func shutdown(forceOnFailure: Bool = false) async {
    await withActionState { [weak self] in
      guard let self else { return }
      try await self.client.shutdownVM(
        node: self.initialVM.node,
        vmid: self.initialVM.vmid,
        force: forceOnFailure,
        timeout: 60
      )
      await self.refresh()
    }
  }

  func reboot() async {
    await withActionState { [weak self] in
      guard let self else { return }
      try await self.client.rebootVM(node: self.initialVM.node, vmid: self.initialVM.vmid)
      await self.refresh()
    }
  }

  func start() async {
    await withActionState { [weak self] in
      guard let self else { return }
      try await self.client.startVM(node: self.initialVM.node, vmid: self.initialVM.vmid)
      await self.refresh()
    }
  }

  func forceStop() async {
    await withActionState { [weak self] in
      guard let self else { return }
      try await self.client.stopVM(node: self.initialVM.node, vmid: self.initialVM.vmid)
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
      let cfg = try await self.client.fetchVMConfig(
        node: self.initialVM.node,
        vmid: self.initialVM.vmid
      )
      self.hardware = Self.groupConfig(cfg)
    } catch {
      self.hardware = []
      self.hardwareError = "Failed to load hardware: \(error.localizedDescription)"
    }
  }

  func fetchBootConfig() async -> (onboot: Bool, freeze: Bool) {
    do {
      let cfg = try await self.client.fetchVMConfig(
        node: self.initialVM.node,
        vmid: self.initialVM.vmid
      )
      let onboot = cfg["onboot"] == "1"
      let freeze = cfg["freeze"] == "1"
      return (onboot, freeze)
    } catch {
      return (false, false)
    }
  }

  func loadStorages() async {
    guard !storagesLoading else { return }
    storagesLoading = true
    storagesError = nil
    defer { storagesLoading = false }

    do {
      let cfg = try await self.client.fetchVMConfig(
        node: self.initialVM.node,
        vmid: self.initialVM.vmid
      )
      
      // Parse disks from config
      var disks: [VMDisk] = []
      let bootdisk = cfg["bootdisk"] ?? ""
      let diskPrefixes = ["scsi", "sata", "ide", "virtio", "efidisk", "tpmstate"]
      
      for (key, value) in cfg {
        for prefix in diskPrefixes {
          if key.hasPrefix(prefix) {
            let isBoot = bootdisk == key || bootdisk.hasPrefix(prefix)
            let parsed = parseDiskConfig(key: key, value: value, isBoot: isBoot)
            disks.append(parsed)
            break
          }
        }
      }
      
      // Sort by available space (least to most) if size is available, otherwise by device name
      disks.sort { disk1, disk2 in
        if let size1 = disk1.size, let size2 = disk2.size {
          return size1 < size2
        }
        return disk1.device < disk2.device
      }
      
      self.vmDisks = disks
    } catch let error as ProxmoxClientError {
      self.vmDisks = []
      // Suppress "ds" parameter errors - these are common and don't affect disk listing
      if case .requestFailed(let code, let message) = error {
        if code == 400 && message.contains("ds") {
          self.storagesError = nil // Don't show error for missing ds parameter
        } else {
          self.storagesError = "Failed to load disks: \(message)"
        }
      } else {
        self.storagesError = "Failed to load disks: \(error.localizedDescription)"
      }
    } catch {
      self.vmDisks = []
      self.storagesError = "Failed to load disks: \(error.localizedDescription)"
    }
  }

  private func parseDiskConfig(key: String, value: String, isBoot: Bool) -> VMDisk {
    // Parse disk config like "local:100/vm-100-disk-0.qcow2,size=32G"
    // or "local-lvm:vm-100-disk-0,size=32G"
    // or "local:100/vm-100-disk-0.qcow2"
    var storage = ""
    var size: Int64? = nil
    
    // Extract storage and size
    if let colonIndex = value.firstIndex(of: ":") {
      storage = String(value[..<colonIndex])
      let afterColon = String(value[value.index(after: colonIndex)...])
      
      // Check for size parameter (can be in format "size=32G" or ",size=32G")
      let components = afterColon.split(separator: ",")
      for component in components {
        let trimmed = component.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("size=") {
          let sizeStr = String(trimmed.dropFirst(5)) // Remove "size="
          size = parseSize(sizeStr)
          break
        }
      }
    } else {
      storage = value
    }
    
    return VMDisk(
      id: key,
      device: key,
      storage: storage,
      size: size,
      isBoot: isBoot,
      rawValue: value
    )
  }

  private func parseSize(_ sizeStr: String) -> Int64? {
    // Parse size like "32G", "500M", "1T"
    let trimmed = sizeStr.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    
    let lastChar = trimmed.last?.lowercased()
    guard let multiplier = lastChar else { return nil }
    
    let numberStr = String(trimmed.dropLast())
    guard let number = Double(numberStr) else { return nil }
    
    let bytes: Double
    switch multiplier {
    case "k": bytes = number * 1024
    case "m": bytes = number * 1024 * 1024
    case "g": bytes = number * 1024 * 1024 * 1024
    case "t": bytes = number * 1024 * 1024 * 1024 * 1024
    default: return nil
    }
    
    return Int64(bytes)
  }

  private static func groupConfig(_ cfg: [String: String]) -> [HardwareSection] {
    func items(_ pairs: [(String, String)]) -> [HardwareItem] { pairs.map { HardwareItem(key: $0.0, value: $0.1) } }
    var sections: [HardwareSection] = []

    let cpuMemKeys = ["sockets","cores","vcpus","cpulimit","cpu","numa","memory","balloon","machine","bios","agent"]
    let cpuMem = cpuMemKeys.compactMap { k in cfg[k].map { (k, $0) } }
    if !cpuMem.isEmpty { sections.append(HardwareSection(title: "CPU & Memory", items: items(cpuMem))) }

    let bootKeys = ["onboot", "boot", "bootdisk"]
    let boot = bootKeys.compactMap { k in cfg[k].map { (k, $0) } }
    if !boot.isEmpty { sections.append(HardwareSection(title: "Boot", items: items(boot))) }

    let diskPrefixes = ["scsi","sata","ide","virtio","efidisk","tpmstate","unused"]
    let diskPairs = cfg.keys.filter { key in diskPrefixes.contains { key.hasPrefix($0) } }
      .sorted().compactMap { k in cfg[k].map { (k, $0) } }
    if !diskPairs.isEmpty { sections.append(HardwareSection(title: "Disks", items: items(diskPairs))) }

    let netPairs = cfg.keys.filter { $0.hasPrefix("net") }.sorted().compactMap { k in cfg[k].map { (k, $0) } }
    if !netPairs.isEmpty { sections.append(HardwareSection(title: "Network", items: items(netPairs))) }

    let displayKeys = ["vga", "video", "serial", "display"]
    let display = displayKeys.compactMap { k in cfg[k].map { (k, $0) } }
    if !display.isEmpty { sections.append(HardwareSection(title: "Display", items: items(display))) }

    let controllerKeys = ["scsihw", "rng0", "smbios1", "args", "agent", "tablet", "keyboard"]
    let controller = controllerKeys.compactMap { k in cfg[k].map { (k, $0) } }
    if !controller.isEmpty { sections.append(HardwareSection(title: "Controllers & Misc", items: items(controller))) }

    let pciPairs = cfg.keys.filter { $0.hasPrefix("hostpci") }.sorted().compactMap { k in cfg[k].map { (k, $0) } }
    if !pciPairs.isEmpty { sections.append(HardwareSection(title: "PCI Passthrough", items: items(pciPairs))) }

    let cloudKeys = ["cicustom","ciuser","cipassword","citype","ipconfig0","ipconfig1"]
    var cloud = cloudKeys.compactMap { k in cfg[k].map { (k, $0) } }
    if let ide2 = cfg["ide2"], ide2.contains("cloudinit") { cloud.append(("ide2", ide2)) }
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

  func updateResources(
    newCores: Int?,
    newSockets: Int?,
    newMemoryMiB: Int?,
    newBalloonMiB: Int?,
    newName: String?,
    onboot: Bool?,
    freeze: Bool?
  ) async -> String? {
    await withActionState { [weak self] in
      guard let self else { return }
      try await self.client.updateVMResources(
        node: self.initialVM.node,
        vmid: self.initialVM.vmid,
        cores: newCores,
        sockets: newSockets,
        memoryMiB: newMemoryMiB,
        balloonMiB: newBalloonMiB,
        name: newName,
        onboot: onboot,
        freeze: freeze
      )
      await self.refresh()
      // Update the VM name in the local model if it was changed
      if let newName = newName {
        self.vm = ProxmoxVM(
          vmid: self.vm.vmid,
          name: newName,
          node: self.vm.node,
          status: self.vm.status,
          cpus: self.vm.cpus,
          maxmem: self.vm.maxmem,
          mem: self.vm.mem,
          uptime: self.vm.uptime,
          netin: self.vm.netin,
          netout: self.vm.netout,
          tags: self.vm.tags
        )
      }
    }
    return self.errorMessage
  }
}
