import Foundation
import os.log

let logger = Logger(subsystem: "dev.jsemolik.pvebuddy", category: "proxmox")

struct ProxmoxNode: Decodable {
    let node: String
}

private struct NodesResponse: Decodable {
    let data: [ProxmoxNode]
}

struct ProxmoxNodeStatus: Decodable {
    let cpu: Double       // 0.0 - 1.0
    let mem: Int64        // bytes used
    let maxmem: Int64     // total bytes
    let swap: Int64       // bytes used
    let maxswap: Int64    // total bytes
    let wait: Double      // I/O delay (fraction or percentage, depending on Proxmox)

    private enum CodingKeys: String, CodingKey {
        case cpu
        case mem
        case maxmem
        case swap
        case maxswap
        case wait
        case memory
    }

    private enum MemoryKeys: String, CodingKey {
        case used
        case total
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // CPU is usually a top-level Double 0.0–1.0; default to 0 if missing.
        cpu = (try? container.decode(Double.self, forKey: .cpu)) ?? 0

        // Proxmox can expose memory either as top-level mem/maxmem or nested memory { used, total }.
        if let memValue = try? container.decode(Int64.self, forKey: .mem),
           let maxmemValue = try? container.decode(Int64.self, forKey: .maxmem) {
            mem = memValue
            maxmem = maxmemValue
        } else if let memoryContainer = try? container.nestedContainer(keyedBy: MemoryKeys.self, forKey: .memory) {
            let used = (try? memoryContainer.decode(Int64.self, forKey: .used)) ?? 0
            let total = (try? memoryContainer.decode(Int64.self, forKey: .total)) ?? 0
            mem = used
            maxmem = total
        } else {
            mem = 0
            maxmem = 0
        }

        // Swap usage if available.
        swap = (try? container.decode(Int64.self, forKey: .swap)) ?? 0
        maxswap = (try? container.decode(Int64.self, forKey: .maxswap)) ?? 0

        // I/O wait / delay – treat values <= 1 as fractions (e.g. 0.12) and larger as percentages.
        let rawWait = (try? container.decode(Double.self, forKey: .wait)) ?? 0
        if rawWait <= 1.0 {
            wait = rawWait * 100.0
        } else {
            wait = rawWait
        }
    }

    // Memberwise initializer so callers can create aggregated statuses.
    init(cpu: Double, mem: Int64, maxmem: Int64, swap: Int64, maxswap: Int64, wait: Double) {
        self.cpu = cpu
        self.mem = mem
        self.maxmem = maxmem
        self.swap = swap
        self.maxswap = maxswap
        self.wait = wait
    }
}

struct ProxmoxStorage: Decodable, Identifiable {
    // Storage name is unique per node; since we already scope by node in the request,
    // this is sufficient for an identifier in the UI.
    var id: String { storage }

    let storage: String
    let type: String
    let total: Int64
    let used: Int64
    let avail: Int64

    private enum CodingKeys: String, CodingKey {
        case storage
        case type
        case total
        case used
        case avail
    }
}

private struct StorageListResponse: Decodable {
    let data: [ProxmoxStorage]
}

struct ProxmoxVMListItem: Decodable {
    let vmid: String
    let name: String
    let node: String
    let status: String
    let type: String

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // vmid may be Int or String
        if let intVmid = try? container.decode(Int.self, forKey: .vmid) {
            vmid = String(intVmid)
        } else if let strVmid = try? container.decode(String.self, forKey: .vmid) {
            vmid = strVmid
        } else {
            vmid = ""
        }

        name = (try? container.decode(String.self, forKey: .name)) ?? ""
        node = (try? container.decode(String.self, forKey: .node)) ?? ""
        status = (try? container.decode(String.self, forKey: .status)) ?? "unknown"
        type = (try? container.decode(String.self, forKey: .type)) ?? ""
    }

    private enum CodingKeys: String, CodingKey {
        case vmid
        case name
        case node
        case status
        case type
    }
}

struct ProxmoxVMDetail: Decodable {
    let cpus: Int
    let maxmem: Int64
    let mem: Int64
    let uptime: Int64?
    let netin: Int64?
    let netout: Int64?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let cp = try? container.decode(Int.self, forKey: .cpus) {
            cpus = cp
        } else if let cp = try? container.decode(Int.self, forKey: .maxcpu) {
            cpus = cp
        } else {
            cpus = 0
        }

        maxmem = (try? container.decode(Int64.self, forKey: .maxmem)) ?? 0
        mem = (try? container.decode(Int64.self, forKey: .mem)) ?? 0
        uptime = try? container.decode(Int64.self, forKey: .uptime)
        netin = try? container.decode(Int64.self, forKey: .netin)
        netout = try? container.decode(Int64.self, forKey: .netout)
    }

    private enum CodingKeys: String, CodingKey {
        case cpus
        case maxcpu
        case maxmem
        case mem
        case uptime
        case netin
        case netout
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
}

private struct VMListResponse: Decodable {
    let data: [ProxmoxVMListItem]
}

private struct VMDetailResponse: Decodable {
    let data: ProxmoxVMDetail
}

private struct NodeStatusResponse: Decodable {
    let data: ProxmoxNodeStatus
}

enum ProxmoxClientError: Error {
    case invalidURL
    case requestFailed(statusCode: Int, message: String)
    case decodingFailed(underlying: Error)
    case noNodesFound
}

final class ProxmoxClient {
    private let baseAddress: String
    private let tokenID: String
    private let tokenSecret: String
    private var cachedNodeName: String?

    /// - Parameter baseAddress: Full base address including scheme and port, e.g. `https://pve.example.com:8006`
    init(baseAddress: String) {
        self.baseAddress = baseAddress.trimmingCharacters(in: .whitespacesAndNewlines)

        let defaults = UserDefaults.standard
        self.tokenID = defaults.string(forKey: "pve_token_id") ?? ""
        self.tokenSecret = defaults.string(forKey: "pve_token_secret") ?? ""
    }

    /// Fetch overall node status (CPU + memory) for the first available node.
    func fetchOverallStatus() async throws -> ProxmoxNodeStatus {
        let node = try await getNodeName()
        return try await fetchStatus(for: node)
    }

    /// Fetch the names of all nodes in the cluster.
    func fetchAllNodeNames() async throws -> [String] {
        let url = try makeURL(path: "/api2/json/nodes")

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        if !tokenID.isEmpty && !tokenSecret.isEmpty {
            let authHeader = "PVEAPIToken=\(tokenID)=\(tokenSecret)"
            request.setValue(authHeader, forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            let body = String(data: data, encoding: .utf8) ?? "<non-UTF8 response>"
            print("❌ Proxmox /nodes request failed – status: \(status), body: \(body)")
            throw ProxmoxClientError.requestFailed(statusCode: status, message: body)
        }

        do {
            let decoded = try JSONDecoder().decode(NodesResponse.self, from: data)
            return decoded.data.map { $0.node }
        } catch {
            print("❌ Failed to decode /nodes response: \(error)")
            throw ProxmoxClientError.decodingFailed(underlying: error)
        }
    }

    /// Fetch status for all nodes and aggregate the results.
    func fetchAllStatus() async throws -> ProxmoxNodeStatus {
        let nodeNames = try await fetchAllNodeNames()
        if nodeNames.isEmpty {
            throw ProxmoxClientError.noNodesFound
        }
        // Fetch each node status concurrently
        let statusTasks = nodeNames.map { node in
            Task { try await fetchStatus(for: node) }
        }
        var statuses: [ProxmoxNodeStatus] = []
        for task in statusTasks {
            do {
                let status = try await task.value
                statuses.append(status)
            } catch {
                // If one node fails, ignore and continue
                print("❌ Failed to fetch status for node: \(error)")
            }
        }
        guard !statuses.isEmpty else {
            throw ProxmoxClientError.noNodesFound
        }
        // Aggregate metrics
        let cpuAvg = statuses.map { $0.cpu }.reduce(0, +) / Double(statuses.count)
        let memSum = statuses.map { $0.mem }.reduce(0, +)
        let maxMemSum = statuses.map { $0.maxmem }.reduce(0, +)
        let swapSum = statuses.map { $0.swap }.reduce(0, +)
        let maxSwapSum = statuses.map { $0.maxswap }.reduce(0, +)
        let waitAvg = statuses.map { $0.wait }.reduce(0, +) / Double(statuses.count)
        return ProxmoxNodeStatus(cpu: cpuAvg, mem: memSum, maxmem: maxMemSum, swap: swapSum, maxswap: maxSwapSum, wait: waitAvg)
    }

    func fetchStoragesForNode() async throws -> [ProxmoxStorage] {
        let node = try await getNodeName()
        return try await fetchStorages(for: node)
    }

    // MARK: - Private helpers

    private func makeURL(path: String) throws -> URL {
        let trimmedBase = baseAddress.hasSuffix("/") ? String(baseAddress.dropLast()) : baseAddress
        guard let url = URL(string: trimmedBase + path) else {
            throw ProxmoxClientError.invalidURL
        }
        return url
    }

    private func getNodeName() async throws -> String {
        if let cachedNodeName {
            return cachedNodeName
        }

        let node = try await fetchFirstNodeName()
        cachedNodeName = node
        return node
    }

    private func fetchFirstNodeName() async throws -> String {
        let url = try makeURL(path: "/api2/json/nodes")

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        if !tokenID.isEmpty && !tokenSecret.isEmpty {
            let authHeader = "PVEAPIToken=\(tokenID)=\(tokenSecret)"
            request.setValue(authHeader, forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            let body = String(data: data, encoding: .utf8) ?? "<non-UTF8 response>"
            print("❌ Proxmox /nodes request failed – status: \(status), body: \(body)")
            throw ProxmoxClientError.requestFailed(statusCode: status, message: body)
        }

        do {
            let decoded = try JSONDecoder().decode(NodesResponse.self, from: data)
            guard let first = decoded.data.first else {
                print("❌ Proxmox /nodes returned no nodes")
                throw ProxmoxClientError.noNodesFound
            }
            return first.node
        } catch {
            print("❌ Failed to decode /nodes response: \(error)")
            throw ProxmoxClientError.decodingFailed(underlying: error)
        }
    }

    func fetchStatus(for node: String) async throws -> ProxmoxNodeStatus {
        let encodedNode = node.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? node
        let url = try makeURL(path: "/api2/json/nodes/\(encodedNode)/status")

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        if !tokenID.isEmpty && !tokenSecret.isEmpty {
            let authHeader = "PVEAPIToken=\(tokenID)=\(tokenSecret)"
            request.setValue(authHeader, forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            let body = String(data: data, encoding: .utf8) ?? "<non-UTF8 response>"
            print("❌ Proxmox /status request failed – status: \(status), body: \(body)")
            throw ProxmoxClientError.requestFailed(statusCode: status, message: body)
        }

        do {
            let decoded = try JSONDecoder().decode(NodeStatusResponse.self, from: data)
            return decoded.data
        } catch {
            let body = String(data: data, encoding: .utf8) ?? "<non-UTF8 response>"
            print("❌ Failed to decode /status response: \(error)")
            print("Raw /status body: \(body)")
            throw ProxmoxClientError.decodingFailed(underlying: error)
        }
    }

    func fetchStorages(for node: String) async throws -> [ProxmoxStorage] {
        let encodedNode = node.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? node
        let url = try makeURL(path: "/api2/json/nodes/\(encodedNode)/storage")

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        if !tokenID.isEmpty && !tokenSecret.isEmpty {
            let authHeader = "PVEAPIToken=\(tokenID)=\(tokenSecret)"
            request.setValue(authHeader, forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            let body = String(data: data, encoding: .utf8) ?? "<non-UTF8 response>"
            print("❌ Proxmox /storage request failed – status: \(status), body: \(body)")
            throw ProxmoxClientError.requestFailed(statusCode: status, message: body)
        }

        do {
            let decoded = try JSONDecoder().decode(StorageListResponse.self, from: data)
            return decoded.data
        } catch {
            let body = String(data: data, encoding: .utf8) ?? "<non-UTF8 response>"
            print("❌ Failed to decode /storage response: \(error)")
            print("Raw /storage body: \(body)")
            throw ProxmoxClientError.decodingFailed(underlying: error)
        }
    }

    /// Fetch all VMs datacenter-wide (across all nodes).
    func fetchAllVMs() async throws -> [ProxmoxVM] {
        print("📡 Starting fetchAllVMs...")
        
        // Step 1: Fetch VM list from cluster/resources
        let listUrl = try makeURL(path: "/api2/json/cluster/resources?type=vm")
        var listRequest = URLRequest(url: listUrl)
        listRequest.httpMethod = "GET"
        let hasAuth = !tokenID.isEmpty && !tokenSecret.isEmpty
        if hasAuth {
            let authHeader = "PVEAPIToken=\(tokenID)=\(tokenSecret)"
            listRequest.setValue(authHeader, forHTTPHeaderField: "Authorization")
        }

        print("➡️ Proxmox request: GET \(listUrl.absoluteString)")
        print("📋 Token ID configured: \(hasAuth)")
        print("🔑 Token ID: '\(tokenID)'")
        print("🔐 Token Secret length: \(tokenSecret.count) chars")

        do {
            let (listData, listResponse) = try await URLSession.shared.data(for: listRequest)

            guard let httpResponse = listResponse as? HTTPURLResponse else {
                print("⚠️ Response is not HTTPURLResponse")
                throw ProxmoxClientError.requestFailed(statusCode: -1, message: "Invalid response type")
            }

            let bodyText = String(data: listData, encoding: .utf8) ?? "<non-UTF8 response>"
            print("⬅️ Proxmox response: status=\(httpResponse.statusCode)")
            print("📦 Response body (first 2000 chars): \(bodyText.prefix(2000))")

            guard 200..<300 ~= httpResponse.statusCode else {
                print("❌ HTTP error: \(httpResponse.statusCode)")
                throw ProxmoxClientError.requestFailed(statusCode: httpResponse.statusCode, message: bodyText)
            }

            // Step 2: Decode the list
            let listDecoded: VMListResponse
            do {
                listDecoded = try JSONDecoder().decode(VMListResponse.self, from: listData)
                print("✅ Decoded \(listDecoded.data.count) VMs from cluster/resources")
            } catch {
                print("❌ Failed to decode /cluster/resources response: \(error)")
                print("Raw response body: \(bodyText)")
                throw ProxmoxClientError.decodingFailed(underlying: error)
            }

            guard !listDecoded.data.isEmpty else {
                print("⚠️ No VMs returned from cluster/resources endpoint")
                return []
            }

            // Step 3: Fetch detailed status for each VM concurrently
            print("🔍 Fetching details for \(listDecoded.data.count) VMs...")
            let detailTasks = listDecoded.data.map { item in
                Task { () -> ProxmoxVM? in
                    do {
                        print("  ↳ Fetching details for VM \(item.vmid) (\(item.name)) on node \(item.node)")
                        let detail = try await self.fetchVMDetail(node: item.node, vmid: item.vmid)
                        let vm = ProxmoxVM(
                            vmid: item.vmid,
                            name: item.name,
                            node: item.node,
                            status: item.status,
                            cpus: detail.cpus,
                            maxmem: detail.maxmem,
                            mem: detail.mem,
                            uptime: detail.uptime,
                            netin: detail.netin,
                            netout: detail.netout
                        )
                        print("  ✅ Successfully fetched VM \(item.vmid)")
                        return vm
                    } catch {
                        print("  ❌ Failed to fetch details for VM \(item.vmid): \(error)")
                        // Return nil for failed VMs; they'll be filtered out below
                        return nil
                    }
                }
            }

            var vms: [ProxmoxVM] = []
            for task in detailTasks {
                if let vm = await task.value {
                    vms.append(vm)
                }
            }

            print("🎉 Successfully fetched \(vms.count) VMs")
            return vms
        } catch {
            print("💥 fetchAllVMs failed with error: \(error)")
            throw error
        }
    }

    func fetchVMDetail(node: String, vmid: String) async throws -> ProxmoxVMDetail {
        let encodedNode = node.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? node
        let encodedVmid = vmid.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? vmid
        let url = try makeURL(path: "/api2/json/nodes/\(encodedNode)/qemu/\(encodedVmid)/status/current")

        print("    🔗 Detail URL: \(url.absoluteString)")

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        if !tokenID.isEmpty && !tokenSecret.isEmpty {
            let authHeader = "PVEAPIToken=\(tokenID)=\(tokenSecret)"
            request.setValue(authHeader, forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            let body = String(data: data, encoding: .utf8) ?? "<non-UTF8 response>"
            print("    ❌ Detail request failed with status \(status): \(body.prefix(500))")
            throw ProxmoxClientError.requestFailed(statusCode: status, message: body)
        }

        do {
            let decoded = try JSONDecoder().decode(VMDetailResponse.self, from: data)
            print("    ✅ Detail decoded successfully")
            return decoded.data
        } catch {
            let body = String(data: data, encoding: .utf8) ?? "<non-UTF8 response>"
            print("    ❌ Failed to decode detail response: \(error)")
            print("    Raw body: \(body.prefix(500))")
            throw ProxmoxClientError.decodingFailed(underlying: error)
        }
    }
}


