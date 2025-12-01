//
//  VmDetailHeader.swift
//  pvebuddy
//
//  Created by Oliver Steiner on 01.12.2025.
//

import SwiftUI

struct VmDetailHeader: View {
    let name: String
    let status: String
    let node: String
    let tags: String?

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if let imageName = DistroImageMapper.imageName(from: tags) {
                Image(imageName)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 52, height: 52)
                    .clipShape(Circle())
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(name).font(.title2.bold())
                HStack(spacing: 12) {
                    VmStatusBadge(status: status)
                    Text(node)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }
}

// Helper used by the header
enum DistroImageMapper {
    static func imageName(from tags: String?) -> String? {
        guard let tags, !tags.isEmpty else { return nil }
        let parts = tags.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
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
}
