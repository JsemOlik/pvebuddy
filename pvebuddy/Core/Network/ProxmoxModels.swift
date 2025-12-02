//
//  ProxmoxModels.swift
//  pvebuddy
//
//  Created by Oliver Steiner on 01.12.2025.
//

import Foundation

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

struct ProxmoxContainer: Decodable, Identifiable {
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
