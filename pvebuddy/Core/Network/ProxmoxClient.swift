//
//  ProxmoxClient.swift
//  pvebuddy
//
//  Created by Oliver Steiner on 01.12.2025.
//

import Foundation
import os.log

let logger = Logger(subsystem: "dev.jsemolik.pvebuddy", category: "proxmox")

struct ProxmoxNode: Decodable { let node: String }
private struct NodesResponse: Decodable { let data: [ProxmoxNode] }

private struct StorageListResponse: Decodable { let data: [ProxmoxStorage] }
private struct VMListResponse: Decodable { let data: [ProxmoxVMListItem] }
private struct VMDetailResponse: Decodable { let data: ProxmoxVMDetail }
private struct NodeStatusResponse: Decodable { let data: ProxmoxNodeStatus }

enum ProxmoxClientError: Error {
  case invalidURL
  case requestFailed(statusCode: Int, message: String)
  case decodingFailed(underlying: Error)
  case noNodesFound
}

struct ProxmoxTaskUPIDResponse: Decodable { let data: String }
struct ProxmoxTaskStatusResponse: Decodable {
  struct Task: Decodable { let status: String; let exitstatus: String? }
  let data: Task
}

struct ProxmoxVMConfigResponse: Decodable { let data: [String: VMConfigValue] }
enum VMConfigValue: Decodable {
  case string(String), int(Int), double(Double), bool(Bool), null
  init(from decoder: Decoder) throws {
    let c = try decoder.singleValueContainer()
    if let s = try? c.decode(String.self) { self = .string(s); return }
    if let i = try? c.decode(Int.self) { self = .int(i); return }
    if let d = try? c.decode(Double.self) { self = .double(d); return }
    if let b = try? c.decode(Bool.self) { self = .bool(b); return }
    if c.decodeNil() { self = .null; return }
    self = .string("")
  }
  var displayString: String {
    switch self {
    case .string(let s): return s
    case .int(let i): return String(i)
    case .double(let d): return String(d)
    case .bool(let b): return b ? "true" : "false"
    case .null: return "—"
    }
  }
}

final class ProxmoxClient {
  private let baseAddress: String
  private let tokenID: String
  private let tokenSecret: String

  init(baseAddress: String) {
    self.baseAddress = baseAddress.trimmingCharacters(in: .whitespacesAndNewlines)
    let defaults = UserDefaults.standard
    self.tokenID = defaults.string(forKey: "pve_token_id") ?? ""
    self.tokenSecret = defaults.string(forKey: "pve_token_secret") ?? ""
  }

  // MARK: - Cluster & Node

  func fetchAllNodeNames() async throws -> [String] {
    let url = try makeURL(path: "/api2/json/nodes")
    let (data, resp) = try await dataGET(url)
    try ensureOK(resp, data)
    do { return try JSONDecoder().decode(NodesResponse.self, from: data).data.map { $0.node } }
    catch { throw ProxmoxClientError.decodingFailed(underlying: error) }
  }

  func fetchAllStatus() async throws -> ProxmoxNodeStatus {
    let nodeNames = try await fetchAllNodeNames()
    if nodeNames.isEmpty { throw ProxmoxClientError.noNodesFound }
    let tasks = nodeNames.map { node in Task { try await self.fetchStatus(for: node) } }
    var statuses: [ProxmoxNodeStatus] = []
    for t in tasks { if let st = try? await t.value { statuses.append(st) } }
    if statuses.isEmpty { throw ProxmoxClientError.noNodesFound }
    let cpuAvg = statuses.map { $0.cpu }.reduce(0, +) / Double(statuses.count)
    let memSum = statuses.map { $0.mem }.reduce(0, +)
    let maxMemSum = statuses.map { $0.maxmem }.reduce(0, +)
    let swapSum = statuses.map { $0.swap }.reduce(0, +)
    let maxSwapSum = statuses.map { $0.maxswap }.reduce(0, +)
    let waitAvg = statuses.map { $0.wait }.reduce(0, +) / Double(statuses.count)
    return ProxmoxNodeStatus(cpu: cpuAvg, mem: memSum, maxmem: maxMemSum, swap: swapSum, maxswap: maxSwapSum, wait: waitAvg)
  }

  func fetchStatus(for node: String) async throws -> ProxmoxNodeStatus {
    let nodeEnc = node.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? node
    let url = try makeURL(path: "/api2/json/nodes/\(nodeEnc)/status")
    let (data, resp) = try await dataGET(url)
    try ensureOK(resp, data)
    do { return try JSONDecoder().decode(NodeStatusResponse.self, from: data).data }
    catch { throw ProxmoxClientError.decodingFailed(underlying: error) }
  }

  func fetchStorages(for node: String) async throws -> [ProxmoxStorage] {
    let nodeEnc = node.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? node
    let url = try makeURL(path: "/api2/json/nodes/\(nodeEnc)/storage")
    let (data, resp) = try await dataGET(url)
    try ensureOK(resp, data)
    do { return try JSONDecoder().decode(StorageListResponse.self, from: data).data }
    catch { throw ProxmoxClientError.decodingFailed(underlying: error) }
  }

  // MARK: - VMs

  func fetchAllVMs() async throws -> [ProxmoxVM] {
    let listUrl = try makeURL(path: "/api2/json/cluster/resources?type=vm")
    var req = URLRequest(url: listUrl)
    req.httpMethod = "GET"
    applyAuth(&req)
    let (listData, listResponse) = try await URLSession.shared.data(for: req)
    try ensureOK(listResponse, listData)

    let listDecoded: VMListResponse
    do { listDecoded = try JSONDecoder().decode(VMListResponse.self, from: listData) }
    catch { throw ProxmoxClientError.decodingFailed(underlying: error) }
    if listDecoded.data.isEmpty { return [] }

    let detailTasks = listDecoded.data.map { item in
      Task { () -> ProxmoxVM? in
        do {
          let d = try await self.fetchVMDetail(node: item.node, vmid: item.vmid)
          return ProxmoxVM(
            vmid: item.vmid,
            name: item.name,
            node: item.node,
            status: item.status,
            cpus: d.cpus,
            maxmem: d.maxmem,
            mem: d.mem,
            uptime: d.uptime,
            netin: d.netin,
            netout: d.netout,
            tags: item.tags
          )
        } catch { return nil }
      }
    }
    var vms: [ProxmoxVM] = []
    for t in detailTasks { if let vm = await t.value { vms.append(vm) } }
    return vms
  }

  func fetchVMDetail(node: String, vmid: String) async throws -> ProxmoxVMDetail {
    let nodeEnc = node.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? node
    let vmidEnc = vmid.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? vmid
    let url = try makeURL(path: "/api2/json/nodes/\(nodeEnc)/qemu/\(vmidEnc)/status/current")
    let (data, resp) = try await dataGET(url)
    try ensureOK(resp, data)
    do { return try JSONDecoder().decode(VMDetailResponse.self, from: data).data }
    catch { throw ProxmoxClientError.decodingFailed(underlying: error) }
  }

  struct VMCurrentStatus {
    let status: String
    let cpuFraction: Double
    let memUsed: Int64
    let memMax: Int64
  }

  func fetchVMCurrentStatus(node: String, vmid: String) async throws -> VMCurrentStatus {
    let nodeEnc = node.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? node
    let vmidEnc = vmid.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? vmid
    let url = try makeURL(path: "/api2/json/nodes/\(nodeEnc)/qemu/\(vmidEnc)/status/current")
    let (data, resp) = try await dataGET(url)
    try ensureOK(resp, data)
    struct Raw: Decodable { let data: [String: JSONAny] }
    let raw = try JSONDecoder().decode(Raw.self, from: data)
    let d = raw.data
    let status = (d["qmpstatus"]?.string ?? d["status"]?.string) ?? "unknown"
    let cpuFraction = d["cpu"]?.double ?? 0.0
    let memUsed = Int64(d["mem"]?.double ?? 0.0)
    let memMax = Int64(d["maxmem"]?.double ?? 0.0)
    return VMCurrentStatus(status: status, cpuFraction: cpuFraction, memUsed: memUsed, memMax: memMax)
  }

  // MARK: - VM Time-series (RRD)

  struct RRDEntry: Decodable {
    let time: Int64
    let cpu: Double?
    let mem: Double?
    let maxmem: Double?
  }
  private struct RRDResponse: Decodable { let data: [RRDEntry] }

  func fetchVMRRD(node: String, vmid: String, timeframe: String = "hour", cf: String = "AVERAGE") async throws -> [RRDEntry] {
    let nodeEnc = node.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? node
    let vmidEnc = vmid.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? vmid
    let url = try makeURL(path: "/api2/json/nodes/\(nodeEnc)/qemu/\(vmidEnc)/rrd?timeframe=\(timeframe)&cf=\(cf)")
    let (data, resp) = try await dataGET(url)
    try ensureOK(resp, data)
    return try JSONDecoder().decode(RRDResponse.self, from: data).data
  }

  // Optional: Node RRD if you later need time-series at node level
  func fetchNodeRRD(node: String, timeframe: String = "hour", cf: String = "AVERAGE") async throws -> [RRDEntry] {
    let nodeEnc = node.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? node
    let url = try makeURL(path: "/api2/json/nodes/\(nodeEnc)/rrd?timeframe=\(timeframe)&cf=\(cf)")
    let (data, resp) = try await dataGET(url)
    try ensureOK(resp, data)
    return try JSONDecoder().decode(RRDResponse.self, from: data).data
  }

  // MARK: - Power Actions

  func startVM(node: String, vmid: String) async throws {
    let upid = try await postStatusAction(node: node, vmid: vmid, action: "start")
    try await waitForTask(node: node, upid: upid)
  }

  func shutdownVM(node: String, vmid: String, force: Bool = false, timeout: Int? = nil) async throws {
    var params: [String: String] = [:]
    if let timeout { params["timeout"] = String(timeout) }
    let upid = try await postStatusAction(node: node, vmid: vmid, action: "shutdown", form: params)
    do {
      try await waitForTask(node: node, upid: upid)
    } catch {
      if force { try await stopVM(node: node, vmid: vmid) }
      else { throw error }
    }
  }

  func rebootVM(node: String, vmid: String) async throws {
    let upid = try await postStatusAction(node: node, vmid: vmid, action: "reboot")
    try await waitForTask(node: node, upid: upid)
  }

  func stopVM(node: String, vmid: String) async throws {
    let upid = try await postStatusAction(node: node, vmid: vmid, action: "stop")
    try await waitForTask(node: node, upid: upid)
  }

  // MARK: - VM Config

  func fetchVMConfig(node: String, vmid: String) async throws -> [String: String] {
    let nodeEnc = node.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? node
    let vmidEnc = vmid.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? vmid
    let url = try makeURL(path: "/api2/json/nodes/\(nodeEnc)/qemu/\(vmidEnc)/config")
    let (data, resp) = try await dataGET(url)
    try ensureOK(resp, data)
    do {
      let decoded = try JSONDecoder().decode(ProxmoxVMConfigResponse.self, from: data)
      var out: [String: String] = [:]
      for (k, v) in decoded.data { out[k] = v.displayString }
      return out
    } catch { throw ProxmoxClientError.decodingFailed(underlying: error) }
  }

  // MARK: - VM Config Update (Resources)

  func updateVMResources(
    node: String,
    vmid: String,
    cores: Int?,
    sockets: Int?,
    memoryMiB: Int?,
    balloonMiB: Int?
  ) async throws {
    let nodeEnc = node.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? node
    let vmidEnc = vmid.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? vmid
    let url = try makeURL(path: "/api2/json/nodes/\(nodeEnc)/qemu/\(vmidEnc)/config")

    var form: [String: String] = [:]
    if let cores { form["cores"] = String(cores) }
    if let sockets { form["sockets"] = String(sockets) }
    if let memoryMiB { form["memory"] = String(memoryMiB) }
    if let balloonMiB { form["balloon"] = String(balloonMiB) }

    let (data, resp) = try await dataPOSTForm(url, form: form)
    try ensureOK(resp, data)
  }

  // MARK: - Web Login (Browser Ticket)

  struct LoginTicketResponse: Decodable {
    let data: LoginData
    struct LoginData: Decodable {
      let ticket: String
      let CSRFPreventionToken: String?
      let username: String
    }
  }

  func loginForWebTicket(username: String, password: String, realm: String = "pam") async throws -> (ticket: String, csrf: String?) {
    let url = try makeURL(path: "/api2/json/access/ticket")

    var req = URLRequest(url: url)
    req.httpMethod = "POST"
    req.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")

    let userWithRealm = username.contains("@") ? username : "\(username)@\(realm)"
    let bodyPairs = [
      "username": userWithRealm,
      "password": password
    ]
    let body = bodyPairs.map { k, v in
      "\(k)=\(v.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? v)"
    }.joined(separator: "&")
    req.httpBody = body.data(using: .utf8)

    let (data, resp) = try await URLSession.shared.data(for: req)
    try ensureOK(resp, data)
    let decoded = try JSONDecoder().decode(LoginTicketResponse.self, from: data)
    return (decoded.data.ticket, decoded.data.CSRFPreventionToken)
  }

  // MARK: - HTTP Helpers

  private func makeURL(path: String) throws -> URL {
    let base = baseAddress.hasSuffix("/") ? String(baseAddress.dropLast()) : baseAddress
    guard let url = URL(string: base + path) else { throw ProxmoxClientError.invalidURL }
    return url
  }

  private func applyAuth(_ req: inout URLRequest) {
    if !tokenID.isEmpty && !tokenSecret.isEmpty {
      let authHeader = "PVEAPIToken=\(tokenID)=\(tokenSecret)"
      req.setValue(authHeader, forHTTPHeaderField: "Authorization")
    }
  }

  private func dataGET(_ url: URL) async throws -> (Data, URLResponse) {
    var req = URLRequest(url: url)
    req.httpMethod = "GET"
    applyAuth(&req)
    return try await URLSession.shared.data(for: req)
  }

  private func dataPOSTForm(_ url: URL, form: [String: String] = [:]) async throws -> (Data, URLResponse) {
    var req = URLRequest(url: url)
    req.httpMethod = "POST"
    applyAuth(&req)
    if !form.isEmpty {
      req.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
      let body = form.map { k, v in "\(k)=\(v.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? v)" }
        .joined(separator: "&")
      req.httpBody = body.data(using: .utf8)
    }
    return try await URLSession.shared.data(for: req)
  }

  private func ensureOK(_ response: URLResponse, _ data: Data) throws {
    guard let http = response as? HTTPURLResponse else {
      throw ProxmoxClientError.requestFailed(statusCode: -1, message: "Invalid response type")
    }
    guard 200..<300 ~= http.statusCode else {
      let body = String(data: data, encoding: .utf8) ?? "<non-UTF8 response>"
      throw ProxmoxClientError.requestFailed(statusCode: http.statusCode, message: body)
    }
  }

  private func postStatusAction(node: String, vmid: String, action: String, form: [String: String] = [:]) async throws -> String {
    let nodeEnc = node.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? node
    let vmidEnc = vmid.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? vmid
    let url = try makeURL(path: "/api2/json/nodes/\(nodeEnc)/qemu/\(vmidEnc)/status/\(action)")
    let (data, resp) = try await dataPOSTForm(url, form: form)
    try ensureOK(resp, data)
    do { return try JSONDecoder().decode(ProxmoxTaskUPIDResponse.self, from: data).data }
    catch { throw ProxmoxClientError.decodingFailed(underlying: error) }
  }

  private func waitForTask(node: String, upid: String, timeoutSeconds: TimeInterval = 120) async throws {
    let nodeEnc = node.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? node
    let upidEnc = upid.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? upid
    let url = try makeURL(path: "/api2/json/nodes/\(nodeEnc)/tasks/\(upidEnc)/status")
    let start = Date()
    while true {
      let (data, resp) = try await dataGET(url)
      try ensureOK(resp, data)
      let status = try JSONDecoder().decode(ProxmoxTaskStatusResponse.self, from: data).data
      if status.status == "stopped" {
        if (status.exitstatus?.lowercased() ?? "ok") == "ok" { return }
        else { throw ProxmoxClientError.requestFailed(statusCode: 200, message: "Task failed: \(status.exitstatus ?? "unknown")") }
      }
      if Date().timeIntervalSince(start) > timeoutSeconds {
        throw ProxmoxClientError.requestFailed(statusCode: 0, message: "Task timeout")
      }
      try? await Task.sleep(nanoseconds: 1_000_000_000)
    }
  }
}

struct JSONAny: Decodable {
  let value: Any
  var string: String? { value as? String }
  var double: Double? {
    if let d = value as? Double { return d }
    if let i = value as? Int { return Double(i) }
    if let s = value as? String, let d = Double(s) { return d }
    return nil
  }
  init(from decoder: Decoder) throws {
    let c = try decoder.singleValueContainer()
    if let b = try? c.decode(Bool.self) { value = b; return }
    if let i = try? c.decode(Int.self) { value = i; return }
    if let d = try? c.decode(Double.self) { value = d; return }
    if let s = try? c.decode(String.self) { value = s; return }
    if c.decodeNil() { value = NSNull(); return }
    value = ""
  }
}
