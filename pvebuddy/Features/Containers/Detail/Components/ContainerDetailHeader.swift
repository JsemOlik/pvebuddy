//
//  ContainerDetailHeader.swift
//  pvebuddy
//
//  Created by Oliver Steiner on 01.12.2025.
//

import SwiftUI

struct ContainerDetailHeader: View {
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
                HStack(alignment: .center, spacing: 8) {
                    Text(name)
                        .font(.title2.bold())
                    
                    if let tags = tags, !tags.isEmpty {
                        TagBadgesView(tags: tags)
                    }
                }
                HStack(spacing: 12) {
                    ContainerStatusBadge(status: status)
                    Text(node)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }
}

private struct TagBadgesView: View {
    let tags: String
    
    var body: some View {
        let tagList = parseTags(tags)
        
        HStack(spacing: 6) {
            ForEach(tagList, id: \.self) { tag in
                TagBadge(tag: tag)
            }
        }
    }
    
    private func parseTags(_ tagsString: String) -> [String] {
        // Handle both comma and semicolon separators
        let separators = CharacterSet(charactersIn: ",;")
        return tagsString.components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

private struct TagBadge: View {
    let tag: String
    
    var body: some View {
        Text(tag)
            .font(.caption2.weight(.medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(colorForTag(tag))
            )
    }
    
    private func colorForTag(_ tag: String) -> Color {
        // Generate a consistent color for each tag based on its hash
        let hash = tag.hashValue
        let colors: [Color] = [
            .blue, .green, .orange, .purple, .pink, .red, .teal, .cyan,
            .indigo, .mint, .yellow, .brown
        ]
        let index = abs(hash) % colors.count
        return colors[index]
    }
}
