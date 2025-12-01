import Foundation

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

    private func fetchStatus(for node: String) async throws -> ProxmoxNodeStatus {
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

    private func fetchStorages(for node: String) async throws -> [ProxmoxStorage] {
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
}


