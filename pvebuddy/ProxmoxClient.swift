import Foundation
import os.log

let logger = Logger(subsystem: "dev.jsemolik.pvebuddy", category: "proxmox")

struct ProxmoxNode: Decodable { let node: String }
private struct NodesResponse: Decodable { let data: [ProxmoxNode] }

struct ProxmoxNodeStatus: Decodable {
  let cpu: Double
  let mem: Int64
  let maxmem: Int64
  let swap: Int64
  let maxswap: Int64
  let wait: Double

  private enum CodingKeys: String, CodingKey { case cpu, mem, maxmem, swap, maxswap, wait, memory }
  private enum MemoryKeys: String, CodingKey { case used, total }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    cpu = (try? c.decode(Double.self, forKey: .cpu)) ?? 0
    if let memValue = try? c.decode(Int64.self, forKey: .mem),
       let maxmemValue = try? c.decode(Int64.self, forKey: .maxmem) {
      mem = memValue; maxmem = maxmemValue
    } else if let mc = try? c.nestedContainer(keyedBy: MemoryKeys.self, forKey: .memory) {
      mem = (try? mc.decode(Int64.self, forKey: .used)) ?? 0
      maxmem = (try? mc.decode(Int64.self, forKey: .total)) ?? 0
    } else { mem = 0; maxmem = 0 }
    swap = (try? c.decode(Int64.self, forKey: .swap)) ?? 0
    maxswap = (try? c.decode(Int64.self, forKey: .maxswap)) ?? 0
    let rawWait = (try? c.decode(Double.self, forKey: .wait)) ?? 0
    wait = rawWait <= 1.0 ? rawWait * 100.0 : rawWait
  }

  init(cpu: Double, mem: Int64, maxmem: Int64, swap: Int64, maxswap: Int64, wait: Double) {
    self.cpu = cpu; self.mem = mem; self.maxmem = maxmem; self.swap = swap; self.maxswap = maxswap; self.wait = wait
  }
}

struct ProxmoxStorage: Decodable, Identifiable {
  var id: String { storage }
  let storage: String
  let type: String
  let total: Int64
  let used: Int64
  let avail: Int64
}
private struct StorageListResponse: Decodable { let data: [ProxmoxStorage] }

struct ProxmoxVMListItem: Decodable {
  let vmid: String
  let name: String
  let node: String
  let status: String
  let type: String
  let tags: String?

  private enum CodingKeys: String, CodingKey { case vmid, name, node, status, type, tags }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    if let intVmid = try? c.decode(Int.self, forKey: .vmid) { vmid = String(intVmid) }
    else if let strVmid = try? c.decode(String.self, forKey: .vmid) { vmid = strVmid }
    else { vmid = "" }
    name = (try? c.decode(String.self, forKey: .name)) ?? ""
    node = (try? c.decode(String.self, forKey: .node)) ?? ""
    status = (try? c.decode(String.self, forKey: .status)) ?? "unknown"
    type = (try? c.decode(String.self, forKey: .type)) ?? ""
    tags = try? c.decode(String.self, forKey: .tags)
  }
}

struct ProxmoxVMDetail: Decodable {
  let cpus: Int
  let maxmem: Int64
  let mem: Int64
  let uptime: Int64?
  let netin: Int64?
  let netout: Int64?

  private enum CodingKeys: String, CodingKey { case cpus, maxcpu, maxmem, mem, uptime, netin, netout }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    if let cp = try? c.decode(Int.self, forKey: .cpus) { cpus = cp }
    else if let cp = try? c.decode(Int.self, forKey: .maxcpu) { cpus = cp }
    else { cpus = 0 }
    maxmem = (try? c.decode(Int64.self, forKey: .maxmem)) ?? 0
    mem = (try? c.decode(Int64.self, forKey: .mem)) ?? 0
    uptime = try? c.decode(Int64.self, forKey: .uptime)
    netin = try? c.decode(Int64.self, forKey: .netin)
    netout = try? c.decode(Int64.self, forKey: .netout)
  }
}

struct ProxmoxVM: Decodable, Identifiable {
  var id: String { vmid }
  let vmid: String
  let name: String
  let node: String
  let status: String
  let cpus: Int
  let maxmem: Int64
  let mem: Int64
  let uptime: Int64?
  let netin: Int64?
  let netout: Int64?
  let tags: String?
}

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

  // MARK: - Web Login (Browser Ticket)

  struct LoginTicketResponse: Decodable {
    let data: LoginData
    struct LoginData: Decodable {
      let ticket: String
      let CSRFPreventionToken: String?
      let username: String
    }
  }

  /// Obtain a browser ticket (PVEAuthCookie) for the Proxmox Web UI.
  /// Requires a real username@realm and password (API tokens do not work here).
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
      try? await Task.sleep(for: .seconds(1))
    }
  }
}

// JSONAny helper can live outside the client
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
