//
//  LxcDetailHeader.swift
//  pvebuddy
//
//  Created by Oliver Steiner on 02.12.2025.
//

import SwiftUI

struct LxcDetailHeader: View {
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
                    LxcStatusBadge(status: status)
                    Text(node)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }
}
