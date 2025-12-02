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
  private let urlSession: URLSession

  init(baseAddress: String) {
    self.baseAddress = baseAddress.trimmingCharacters(in: .whitespacesAndNewlines)
    let defaults = UserDefaults.standard
    self.tokenID = defaults.string(forKey: "pve_token_id") ?? ""
    self.tokenSecret = defaults.string(forKey: "pve_token_secret") ?? ""
    
    // Create a custom URLSession configuration for better control
    let config = URLSessionConfiguration.default
    config.httpShouldSetCookies = false
    config.httpCookieAcceptPolicy = .never
    config.httpAdditionalHeaders = [:]
    // Ensure headers are not modified by the system
    config.httpMaximumConnectionsPerHost = 10
    config.timeoutIntervalForRequest = 30
    config.timeoutIntervalForResource = 60
    self.urlSession = URLSession(configuration: config)
    
    // Debug logging for authentication
    if self.tokenID.isEmpty || self.tokenSecret.isEmpty {
      logger.warning("⚠️ ProxmoxClient initialized with empty token - ID: \(self.tokenID.isEmpty ? "empty" : "set"), Secret: \(self.tokenSecret.isEmpty ? "empty" : "set")")
      NSLog("⚠️ ProxmoxClient: Token ID is \(self.tokenID.isEmpty ? "EMPTY" : "set"), Token Secret is \(self.tokenSecret.isEmpty ? "EMPTY" : "set")")
    }
  }

  // MARK: - Cluster & Node

  func fetchAllNodeNames() async throws -> [String] {
    let url = try makeURL(path: "/api2/json/nodes")
    let (data, resp) = try await dataGET(url)
    try ensureOK(resp, data)
    do {
      return try JSONDecoder().decode(NodesResponse.self, from: data).data.map { $0.node }
    } catch {
      throw ProxmoxClientError.decodingFailed(underlying: error)
    }
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
    return ProxmoxNodeStatus(
      cpu: cpuAvg,
      mem: memSum,
      maxmem: maxMemSum,
      swap: swapSum,
      maxswap: maxSwapSum,
      wait: waitAvg
    )
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

  // MARK: - VMs (QEMU)

  /// Fetch VM list with statuses only (no detail fetching) - useful for monitoring
  func fetchVMListWithStatuses() async throws -> [ProxmoxVMListItem] {
    let listUrl = try makeURL(path: "/api2/json/cluster/resources?type=vm")
    var req = URLRequest(url: listUrl)
    req.httpMethod = "GET"
    applyAuth(&req)
    let (listData, listResponse) = try await URLSession.shared.data(for: req)
    try ensureOK(listResponse, listData)

    let listDecoded: VMListResponse
    do { listDecoded = try JSONDecoder().decode(VMListResponse.self, from: listData) }
    catch { throw ProxmoxClientError.decodingFailed(underlying: error) }
    return listDecoded.data
  }

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
        } catch let error as ProxmoxClientError {
          // Silently skip VMs that can't be fetched (e.g., deleted, missing config)
          // Only log if it's not an expected error (500 with "does not exist")
          if case .requestFailed(let code, let message) = error {
            if code != 500 || !message.contains("does not exist") {
              // Log unexpected errors
              print("⚠️ Failed to fetch details for VM \(item.vmid) on \(item.node): \(message)")
            }
          }
          return nil
        } catch {
          // Log other unexpected errors
          print("⚠️ Unexpected error fetching VM \(item.vmid): \(error.localizedDescription)")
          return nil
        }
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
    return VMCurrentStatus(
      status: status,
      cpuFraction: cpuFraction,
      memUsed: memUsed,
      memMax: memMax
    )
  }

  // MARK: - VM Time-series (RRD)

  struct RRDEntry: Decodable {
    let time: Int64
    let cpu: Double?
    let mem: Double?
    let maxmem: Double?
  }
  private struct RRDResponse: Decodable { let data: [RRDEntry] }

  func fetchVMRRD(
    node: String,
    vmid: String,
    timeframe: String = "hour",
    cf: String = "AVERAGE"
  ) async throws -> [RRDEntry] {
    let nodeEnc = node.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? node
    let vmidEnc = vmid.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? vmid
    let url = try makeURL(
      path: "/api2/json/nodes/\(nodeEnc)/qemu/\(vmidEnc)/rrd?timeframe=\(timeframe)&cf=\(cf)"
    )
    let (data, resp) = try await dataGET(url)
    try ensureOK(resp, data)
    return try JSONDecoder().decode(RRDResponse.self, from: data).data
  }

  func fetchNodeRRD(
    node: String,
    timeframe: String = "hour",
    cf: String = "AVERAGE"
  ) async throws -> [RRDEntry] {
    let nodeEnc = node.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? node
    let url = try makeURL(
      path: "/api2/json/nodes/\(nodeEnc)/rrd?timeframe=\(timeframe)&cf=\(cf)"
    )
    let (data, resp) = try await dataGET(url)
    try ensureOK(resp, data)
    return try JSONDecoder().decode(RRDResponse.self, from: data).data
  }

  func fetchLXCRRD(
    node: String,
    vmid: String,
    timeframe: String = "hour",
    cf: String = "AVERAGE"
  ) async throws -> [RRDEntry] {
    let nodeEnc = node.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? node
    let vmidEnc = vmid.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? vmid
    let url = try makeURL(
      path: "/api2/json/nodes/\(nodeEnc)/lxc/\(vmidEnc)/rrd?timeframe=\(timeframe)&cf=\(cf)"
    )
    let (data, resp) = try await dataGET(url)
    try ensureOK(resp, data)
    return try JSONDecoder().decode(RRDResponse.self, from: data).data
  }

  // MARK: - VM Power Actions

  func startVM(node: String, vmid: String) async throws {
    let upid = try await postStatusAction(node: node, vmid: vmid, action: "start")
    try await waitForTask(node: node, upid: upid)
  }

  func shutdownVM(
    node: String,
    vmid: String,
    force: Bool = false,
    timeout: Int? = nil
  ) async throws {
    var params: [String: String] = [:]
    if let timeout { params["timeout"] = String(timeout) }
    let upid = try await postStatusAction(
      node: node,
      vmid: vmid,
      action: "shutdown",
      form: params
    )
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
    } catch {
      throw ProxmoxClientError.decodingFailed(underlying: error)
    }
  }

  // MARK: - VM Config Update (Resources)

  func updateVMResources(
    node: String,
    vmid: String,
    cores: Int?,
    sockets: Int?,
    memoryMiB: Int?,
    balloonMiB: Int?,
    name: String?,
    onboot: Bool?,
    freeze: Bool?
  ) async throws {
    let nodeEnc = node.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? node
    let vmidEnc = vmid.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? vmid
    let url = try makeURL(path: "/api2/json/nodes/\(nodeEnc)/qemu/\(vmidEnc)/config")

    var form: [String: String] = [:]
    if let cores { form["cores"] = String(cores) }
    if let sockets { form["sockets"] = String(sockets) }
    if let memoryMiB { form["memory"] = String(memoryMiB) }
    if let balloonMiB { form["balloon"] = String(balloonMiB) }
    if let name { form["name"] = name }
    if let onboot { form["onboot"] = onboot ? "1" : "0" }
    if let freeze { form["freeze"] = freeze ? "1" : "0" }

    let (data, resp) = try await dataPOSTForm(url, form: form)
    try ensureOK(resp, data)
  }

  // MARK: - LXC Power Actions

  func startLXC(node: String, vmid: String) async throws {
    let upid = try await postLXCStatusAction(node: node, vmid: vmid, action: "start")
    try await waitForTask(node: node, upid: upid)
  }

  func shutdownLXC(
    node: String,
    vmid: String,
    force: Bool = false,
    timeout: Int? = nil
  ) async throws {
    var params: [String: String] = [:]
    if let timeout { params["timeout"] = String(timeout) }
    let upid = try await postLXCStatusAction(
      node: node,
      vmid: vmid,
      action: "shutdown",
      form: params
    )
    do {
      try await waitForTask(node: node, upid: upid)
    } catch {
      if force { try await stopLXC(node: node, vmid: vmid) }
      else { throw error }
    }
  }

  func rebootLXC(node: String, vmid: String) async throws {
    let upid = try await postLXCStatusAction(node: node, vmid: vmid, action: "reboot")
    try await waitForTask(node: node, upid: upid)
  }

  func stopLXC(node: String, vmid: String) async throws {
    let upid = try await postLXCStatusAction(node: node, vmid: vmid, action: "stop")
    try await waitForTask(node: node, upid: upid)
  }

  // MARK: - LXC Config

  func fetchLXCConfig(node: String, vmid: String) async throws -> [String: String] {
    let nodeEnc = node.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? node
    let vmidEnc = vmid.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? vmid
    let url = try makeURL(path: "/api2/json/nodes/\(nodeEnc)/lxc/\(vmidEnc)/config")
    let (data, resp) = try await dataGET(url)
    try ensureOK(resp, data)
    do {
      let decoded = try JSONDecoder().decode(ProxmoxVMConfigResponse.self, from: data)
      var out: [String: String] = [:]
      for (k, v) in decoded.data { out[k] = v.displayString }
      return out
    } catch {
      throw ProxmoxClientError.decodingFailed(underlying: error)
    }
  }

  // MARK: - LXC Config Update (Resources)

  func updateLXCResources(
    node: String,
    vmid: String,
    cores: Int?,
    memoryMiB: Int?,
    swapMiB: Int?,
    onboot: Bool?
  ) async throws {
    let nodeEnc = node.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? node
    let vmidEnc = vmid.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? vmid
    let url = try makeURL(path: "/api2/json/nodes/\(nodeEnc)/lxc/\(vmidEnc)/config")

    var form: [String: String] = [:]
    if let cores { form["cores"] = String(cores) }
    if let memoryMiB { form["memory"] = String(memoryMiB) }
    if let swapMiB { form["swap"] = String(swapMiB) }
    if let onboot { form["onboot"] = onboot ? "1" : "0" }

    let (data, resp) = try await dataPUTForm(url, form: form)
    try ensureOK(resp, data)
  }

  // MARK: - LXC Current Status

  func fetchLXCCurrentStatus(node: String, vmid: String) async throws -> VMCurrentStatus {
    let nodeEnc = node.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? node
    let vmidEnc = vmid.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? vmid
    let url = try makeURL(path: "/api2/json/nodes/\(nodeEnc)/lxc/\(vmidEnc)/status/current")
    let (data, resp) = try await dataGET(url)
    try ensureOK(resp, data)
    struct Raw: Decodable { let data: [String: JSONAny] }
    let raw = try JSONDecoder().decode(Raw.self, from: data)
    let d = raw.data
    let status = d["status"]?.string ?? "unknown"
    let cpuFraction = d["cpu"]?.double ?? 0.0
    let memUsed = Int64(d["mem"]?.double ?? 0.0)
    let memMax = Int64(d["maxmem"]?.double ?? 0.0)
    return VMCurrentStatus(
      status: status,
      cpuFraction: cpuFraction,
      memUsed: memUsed,
      memMax: memMax
    )
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

  func loginForWebTicket(
    username: String,
    password: String,
    realm: String = "pam"
  ) async throws -> (ticket: String, csrf: String?) {
    let url = try makeURL(path: "/api2/json/access/ticket")

    var req = URLRequest(url: url)
    req.httpMethod = "POST"
    req.setValue(
      "application/x-www-form-urlencoded; charset=utf-8",
      forHTTPHeaderField: "Content-Type"
    )

    let userWithRealm = username.contains("@") ? username : "\(username)@\(realm)"
    let bodyPairs = [
      "username": userWithRealm,
      "password": password
    ]
    let body = bodyPairs
      .map { k, v in
        "\(k)=\(v.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? v)"
      }
      .joined(separator: "&")
    req.httpBody = body.data(using: .utf8)

    let (data, resp) = try await urlSession.data(for: req)
    try ensureOK(resp, data)
    let decoded = try JSONDecoder().decode(LoginTicketResponse.self, from: data)
    return (decoded.data.ticket, decoded.data.CSRFPreventionToken)
  }

  // MARK: - HTTP Helpers

  private func makeURL(path: String) throws -> URL {
    let base = baseAddress.hasSuffix("/") ? String(baseAddress.dropLast()) : baseAddress
    guard let url = URL(string: base + path) else {
      throw ProxmoxClientError.invalidURL
    }
    return url
  }

  private func applyAuth(_ req: inout URLRequest) {
    // Re-read tokens from UserDefaults on each request to ensure we have the latest values
    // This is important because tokens might be updated after client initialization
    let defaults = UserDefaults.standard
    var currentTokenID = defaults.string(forKey: "pve_token_id") ?? ""
    var currentTokenSecret = defaults.string(forKey: "pve_token_secret") ?? ""
    
    // Trim whitespace from tokens (common issue when copying/pasting)
    currentTokenID = currentTokenID.trimmingCharacters(in: .whitespacesAndNewlines)
    currentTokenSecret = currentTokenSecret.trimmingCharacters(in: .whitespacesAndNewlines)
    
    if !currentTokenID.isEmpty && !currentTokenSecret.isEmpty {
      // Proxmox API format: PVEAPIToken=USER@REALM!TOKENID=UUID
      // The tokenID should already include user@realm!tokenid format
      // IMPORTANT: Do not URL-encode the header value - it must be sent as-is
      let authHeader = "PVEAPIToken=\(currentTokenID)=\(currentTokenSecret)"
      req.setValue(authHeader, forHTTPHeaderField: "Authorization")
      
      // Verify the header was set correctly (for debugging)
      #if DEBUG
      if let setHeader = req.value(forHTTPHeaderField: "Authorization") {
        logger.debug("Auth header set: \(setHeader.prefix(50))...")
      } else {
        logger.warning("⚠️ Authorization header was not set!")
        NSLog("⚠️ Authorization header verification failed for \(req.url?.absoluteString ?? "unknown")")
      }
      #endif
    } else {
      // If tokens are empty, log a warning
      logger.warning("⚠️ Attempting API request without authentication tokens")
      NSLog("⚠️ ProxmoxClient: No authentication tokens available for request to \(req.url?.absoluteString ?? "unknown")")
    }
  }

  private func dataGET(_ url: URL) async throws -> (Data, URLResponse) {
    var req = URLRequest(url: url)
    req.httpMethod = "GET"
    applyAuth(&req)
    
    do {
      return try await urlSession.data(for: req)
    } catch {
      // Enhanced error logging for network issues
      if let urlError = error as? URLError {
        NSLog("❌ Network error on GET \(url.absoluteString):")
        NSLog("   Code: \(urlError.code.rawValue)")
        NSLog("   Description: \(urlError.localizedDescription)")
        if let underlyingError = (error as NSError).userInfo[NSUnderlyingErrorKey] as? NSError {
          NSLog("   Underlying: \(underlyingError.localizedDescription)")
        }
      }
      throw error
    }
  }

  private func dataPOSTForm(
    _ url: URL,
    form: [String: String] = [:]
  ) async throws -> (Data, URLResponse) {
    var req = URLRequest(url: url)
    req.httpMethod = "POST"
    applyAuth(&req)
    if !form.isEmpty {
      req.setValue(
        "application/x-www-form-urlencoded; charset=utf-8",
        forHTTPHeaderField: "Content-Type"
      )
      let body = form
        .map { k, v in
          "\(k)=\(v.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? v)"
        }
        .joined(separator: "&")
      req.httpBody = body.data(using: .utf8)
    }
    
    do {
      return try await urlSession.data(for: req)
    } catch {
      // Enhanced error logging for network issues
      if let urlError = error as? URLError {
        NSLog("❌ Network error on POST \(url.absoluteString):")
        NSLog("   Code: \(urlError.code.rawValue)")
        NSLog("   Description: \(urlError.localizedDescription)")
        if let underlyingError = (error as NSError).userInfo[NSUnderlyingErrorKey] as? NSError {
          NSLog("   Underlying: \(underlyingError.localizedDescription)")
        }
      }
      throw error
    }
  }

  private func dataPUTForm(
    _ url: URL,
    form: [String: String] = [:]
  ) async throws -> (Data, URLResponse) {
    var req = URLRequest(url: url)
    req.httpMethod = "PUT"
    applyAuth(&req)
    if !form.isEmpty {
      req.setValue(
        "application/x-www-form-urlencoded; charset=utf-8",
        forHTTPHeaderField: "Content-Type"
      )
      let body = form
        .map { k, v in
          "\(k)=\(v.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? v)"
        }
        .joined(separator: "&")
      req.httpBody = body.data(using: .utf8)
    }
    
    do {
      return try await urlSession.data(for: req)
    } catch {
      // Enhanced error logging for network issues
      if let urlError = error as? URLError {
        NSLog("❌ Network error on PUT \(url.absoluteString):")
        NSLog("   Code: \(urlError.code.rawValue)")
        NSLog("   Description: \(urlError.localizedDescription)")
        if let underlyingError = (error as NSError).userInfo[NSUnderlyingErrorKey] as? NSError {
          NSLog("   Underlying: \(underlyingError.localizedDescription)")
        }
      }
      throw error
    }
  }

  private func ensureOK(_ response: URLResponse, _ data: Data) throws {
    guard let http = response as? HTTPURLResponse else {
      throw ProxmoxClientError.requestFailed(
        statusCode: -1,
        message: "Invalid response type"
      )
    }
    guard 200..<300 ~= http.statusCode else {
      let body = String(data: data, encoding: .utf8) ?? "<non-UTF8 response>"
      
      // Suppress verbose logging for expected errors (e.g., missing VM config files)
      // These are common when VMs are deleted or in transition states
      let isExpectedError = http.statusCode == 500 && (
        body.contains("does not exist") ||
        body.contains("Configuration file") ||
        body.contains("not found") ||
        body.contains("does not exist\n")
      )
      
      // For 401 errors, always log with additional context
      if http.statusCode == 401 {
        let defaults = UserDefaults.standard
        var tokenID = defaults.string(forKey: "pve_token_id") ?? ""
        var tokenSecret = defaults.string(forKey: "pve_token_secret") ?? ""
        tokenID = tokenID.trimmingCharacters(in: .whitespacesAndNewlines)
        tokenSecret = tokenSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Show the actual auth header format (without exposing full secret)
        let authHeaderPreview = "PVEAPIToken=\(tokenID)=\(tokenSecret.isEmpty ? "EMPTY" : "***")"
        
        logger.error("HTTP 401 Authentication failed. Token ID: \(tokenID.isEmpty ? "EMPTY" : "present"), Token Secret: \(tokenSecret.isEmpty ? "EMPTY" : "present")")
        NSLog("❌ Proxmox API authentication failed (HTTP 401)")
        NSLog("   Token ID: \(tokenID.isEmpty ? "EMPTY" : tokenID)")
        NSLog("   Token Secret: \(tokenSecret.isEmpty ? "EMPTY" : "present (\(tokenSecret.count) chars)")")
        NSLog("   Auth Header Format: \(authHeaderPreview)")
        if let httpResponse = response as? HTTPURLResponse {
          if let url = httpResponse.url {
            NSLog("   URL: \(url.absoluteString)")
          }
          // Log all response headers for debugging
          NSLog("   Response Headers: \(httpResponse.allHeaderFields)")
        }
        NSLog("   Response Body: %@", body.isEmpty ? "(empty - this might indicate a network/proxy issue)" : body)
        
        // Check if token format looks correct
        if !tokenID.isEmpty {
          let hasAtSymbol = tokenID.contains("@")
          let hasExclamation = tokenID.contains("!")
          if !hasAtSymbol || !hasExclamation {
            NSLog("   ⚠️ Token ID format might be incorrect - should be: user@realm!tokenname")
            NSLog("   Current format: \(hasAtSymbol ? "has @" : "missing @"), \(hasExclamation ? "has !" : "missing !")")
          }
        }
        
        // Additional device-specific debugging
        #if targetEnvironment(simulator)
        NSLog("   Environment: Simulator")
        #else
        NSLog("   Environment: Physical Device")
        NSLog("   ⚠️ This is a physical device - check for:")
        NSLog("      - VPN/Proxy settings that might modify headers")
        NSLog("      - Certificate trust issues (Settings > General > About > Certificate Trust Settings)")
        NSLog("      - Network restrictions or firewall rules")
        #endif
      } else if !isExpectedError {
        // Only log unexpected errors
        logger.error("HTTP \(http.statusCode) error: \(body)")
        NSLog("❌ Proxmox API error (HTTP \(http.statusCode)): %@", body)
      }
      // For expected errors, we silently skip logging to reduce console noise
      
      throw ProxmoxClientError.requestFailed(
        statusCode: http.statusCode,
        message: body
      )
    }
  }

  private func postStatusAction(
    node: String,
    vmid: String,
    action: String,
    form: [String: String] = [:]
  ) async throws -> String {
    let nodeEnc = node.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? node
    let vmidEnc = vmid.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? vmid
    let url = try makeURL(
      path: "/api2/json/nodes/\(nodeEnc)/qemu/\(vmidEnc)/status/\(action)"
    )
    let (data, resp) = try await dataPOSTForm(url, form: form)
    try ensureOK(resp, data)
    do { return try JSONDecoder().decode(ProxmoxTaskUPIDResponse.self, from: data).data }
    catch { throw ProxmoxClientError.decodingFailed(underlying: error) }
  }

  private func waitForTask(
    node: String,
    upid: String,
    timeoutSeconds: TimeInterval = 120
  ) async throws {
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
        else {
          throw ProxmoxClientError.requestFailed(
            statusCode: 200,
            message: "Task failed: \(status.exitstatus ?? "unknown")"
          )
        }
      }
      if Date().timeIntervalSince(start) > timeoutSeconds {
        throw ProxmoxClientError.requestFailed(
          statusCode: 0,
          message: "Task timeout"
        )
      }
      try? await Task.sleep(nanoseconds: 1_000_000_000)
    }
  }

  // MARK: - LXC Helper

  private func postLXCStatusAction(
    node: String,
    vmid: String,
    action: String,
    form: [String: String] = [:]
  ) async throws -> String {
    let nodeEnc = node.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? node
    let vmidEnc = vmid.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? vmid
    let url = try makeURL(
      path: "/api2/json/nodes/\(nodeEnc)/lxc/\(vmidEnc)/status/\(action)"
    )
    let (data, resp) = try await dataPOSTForm(url, form: form)
    try ensureOK(resp, data)
    do { return try JSONDecoder().decode(ProxmoxTaskUPIDResponse.self, from: data).data }
    catch { throw ProxmoxClientError.decodingFailed(underlying: error) }
  }

  // MARK: - LXC Detail

  func fetchLXCDetail(node: String, vmid: String) async throws -> ProxmoxVMDetail {
    let nodeEnc = node.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? node
    let vmidEnc = vmid.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? vmid
    let url = try makeURL(
      path: "/api2/json/nodes/\(nodeEnc)/lxc/\(vmidEnc)/status/current"
    )
    let (data, resp) = try await dataGET(url)
    try ensureOK(resp, data)
    do {
      return try JSONDecoder().decode(VMDetailResponse.self, from: data).data
    } catch {
      throw ProxmoxClientError.decodingFailed(underlying: error)
    }
  }
}

// MARK: - JSONAny helper

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

// MARK: - Containers (Cluster list + enrichment)

extension ProxmoxClient {
  func fetchAllContainers() async throws -> [ProxmoxContainer] {
    // 1) Get all resources from cluster (vmid is used for both VMs and containers)
    let listURL = try makeURL(path: "/api2/json/cluster/resources")
    let (listData, listResp) = try await dataGET(listURL)
    try ensureOK(listResp, listData)
    
    // 2) Decode all resources and filter for LXC containers (type == "lxc")
    let allResources: VMListResponse
    do {
      allResources = try JSONDecoder().decode(VMListResponse.self, from: listData)
    } catch {
      throw ProxmoxClientError.decodingFailed(underlying: error)
    }
    
    // Filter for LXC containers (type == "lxc")
    let containerResources = allResources.data.filter { $0.type == "lxc" }
    if containerResources.isEmpty { return [] }

    // 3) For each container, fetch details from /api2/json/nodes/{node}/lxc/{vmid}/status/current
    let detailTasks = containerResources.map { item in
      Task { () -> ProxmoxContainer? in
        do {
          let d = try await self.fetchLXCDetail(node: item.node, vmid: item.vmid)
          return ProxmoxContainer(
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
        } catch {
          return nil
        }
      }
    }

    var containers: [ProxmoxContainer] = []
    for t in detailTasks {
      if let ct = await t.value { containers.append(ct) }
    }
    return containers
  }
}
