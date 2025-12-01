//
//  FormatHelpers.swift
//  pvebuddy
//
//  Created by Oliver Steiner on 01.12.2025.
//

import Foundation

enum ByteFormatter {
    static func format(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useTB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
