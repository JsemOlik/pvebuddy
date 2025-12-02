//
//  LxcDetailViewModel.swift
//  pvebuddy
//
//  Created by Oliver Steiner on 02.12.2025.
//

import Foundation
import SwiftUI
import Combine

@MainActor
final class LxcDetailViewModel: ObservableObject {
  @Published var container: ProxmoxContainer
  @Published var isLoading: Bool = false
  @Published var errorMessage: String?
  @Published var isActing: Bool = false

  @Published var liveStatus: String = "unknown"
  @Published var cpuPercent: Double = 0.0
  @Published var memUsed: Int64 = 0
  @Published var memMax: Int64 = 0
  @Published var displayedUptime: Int64 = 0

  @Published var nodeStatus: ProxmoxNodeStatus?

  @Published var hardware: [HardwareSection] = []
  @Published var hardwareLoading: Bool = false
  @Published var hardwareError: String?

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

  func loadNodeStatus() async {
    do {
      self.nodeStatus = try await client.fetchStatus(for: initialContainer.node)
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
      self.errorMessage = "Failed to refresh container details: \(error.localizedDescription)"
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
      self.hardware = Self.groupConfig(cfg)
    } catch {
      self.hardware = []
      self.hardwareError = "Failed to load hardware: \(error.localizedDescription)"
    }
  }

  private static func groupConfig(_ cfg: [String: String]) -> [HardwareSection] {
    func items(_ pairs: [(String, String)]) -> [HardwareItem] { pairs.map { HardwareItem(key: $0.0, value: $0.1) } }
    var sections: [HardwareSection] = []

    let cpuMemKeys = ["cores","cpulimit","cpuunits","memory","swap","hostname","arch","ostype"]
    let cpuMem = cpuMemKeys.compactMap { k in cfg[k].map { (k, $0) } }
    if !cpuMem.isEmpty { sections.append(HardwareSection(title: "CPU & Memory", items: items(cpuMem))) }

    let bootKeys = ["onboot", "startup", "protection"]
    let boot = bootKeys.compactMap { k in cfg[k].map { (k, $0) } }
    if !boot.isEmpty { sections.append(HardwareSection(title: "Boot", items: items(boot))) }

    let storagePrefixes = ["rootfs","mp"]
    let storagePairs = cfg.keys.filter { key in storagePrefixes.contains { key.hasPrefix($0) } }
      .sorted().compactMap { k in cfg[k].map { (k, $0) } }
    if !storagePairs.isEmpty { sections.append(HardwareSection(title: "Storage", items: items(storagePairs))) }

    let netPairs = cfg.keys.filter { $0.hasPrefix("net") }.sorted().compactMap { k in cfg[k].map { (k, $0) } }
    if !netPairs.isEmpty { sections.append(HardwareSection(title: "Network", items: items(netPairs))) }

    let featuresKeys = ["features","unprivileged","nesting","fuse","keyctl"]
    let features = featuresKeys.compactMap { k in cfg[k].map { (k, $0) } }
    if !features.isEmpty { sections.append(HardwareSection(title: "Features", items: items(features))) }

    let consoleKeys = ["console","tty","cmode"]
    let console = consoleKeys.compactMap { k in cfg[k].map { (k, $0) } }
    if !console.isEmpty { sections.append(HardwareSection(title: "Console", items: items(console))) }

    let usedKeys = Set(sections.flatMap { $0.items.map { $0.key } })
    let otherPairs = cfg.keys.filter { !usedKeys.contains($0) }.sorted().compactMap { k in cfg[k].map { (k, $0) } }
    if !otherPairs.isEmpty { sections.append(HardwareSection(title: "Other", items: items(otherPairs))) }

    return sections
  }

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
