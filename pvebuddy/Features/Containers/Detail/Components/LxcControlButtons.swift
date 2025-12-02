//
//  LxcControlButtons.swift
//  pvebuddy
//
//  Created by Oliver Steiner on 02.12.2025.
//

import SwiftUI

struct LxcControlButtons: View {
    let onShutdown: () -> Void
    let onForceStop: () -> Void
    let onReboot: () -> Void
    let onStart: () -> Void
    let onConsole: () -> Void
    let onEditResources: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Menu {
                Button { onShutdown() } label: {
                    HStack {
                        Image(systemName: "power").foregroundStyle(.blue)
                        Text("Shutdown").foregroundStyle(.primary)
                    }
                }
                Button { onForceStop() } label: {
                    HStack {
                        Image(systemName: "stop.fill").foregroundStyle(.blue)
                        Text("Force Stop").foregroundStyle(.primary)
                    }
                }
            } label: {
                ZStack {
                    Circle().fill(Color.red)
                    Image(systemName: "power")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 50, height: 50)
            }
            .menuIndicator(.hidden)
            .buttonStyle(.plain)

            Button(action: onReboot) {
                ZStack {
                    Circle().fill(Color.yellow)
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.black)
                }
                .frame(width: 50, height: 50)
            }
            .buttonStyle(.plain)

            Button(action: onStart) {
                ZStack {
                    Circle().fill(Color.green)
                    Image(systemName: "play.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 50, height: 50)
            }
            .buttonStyle(.plain)

            Button(action: onConsole) {
                ZStack {
                    Circle().fill(Color.blue)
                    Image(systemName: "terminal")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 50, height: 50)
            }
            .buttonStyle(.plain)

            Spacer()

            Button(action: onEditResources) {
                ZStack {
                    Circle().fill(Color.blue)
                    Image(systemName: "pencil")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 50, height: 50)
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 12)
    }
}
