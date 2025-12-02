//
//  MainTabView.swift
//  pvebuddy
//
//  Created by Oliver Steiner on 01.12.2025.
//

import SwiftUI
import UIKit

struct MainTabView: View {
    @AppStorage("pve_server_address") private var storedServerAddress: String = ""
    @AppStorage("appearance_preference") private var appearancePreference: Int = 0 // 0: System, 1: Light, 2: Dark
    @AppStorage("notifications_enabled") private var notificationsEnabled: Bool = false

    private var preferredScheme: ColorScheme? {
        switch appearancePreference {
        case 1: return .light
        case 2: return .dark
        default: return nil
        }
    }

    var body: some View {
        TabView {
            NavigationStack {
                if storedServerAddress.isEmpty {
                    MissingServerConfigurationView()
                } else {
                    DashboardView(serverAddress: storedServerAddress)
                }
            }
            .tabItem {
                Image(systemName: "gauge.medium")
                Text("Dashboard")
            }

            VMsView()
            .tabItem {
                Image(systemName: "display")
                Text("VMs")
            }

            ContainersView()
            .tabItem {
                Image(systemName: "cube.transparent")
                Text("LXCs")
            }

            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Image(systemName: "gearshape")
                Text("Settings")
            }
        }
        .tint(.blue)
        .preferredColorScheme(preferredScheme)
        .task {
            await startMonitoringIfNeeded()
        }
        .onChange(of: notificationsEnabled) { _, newValue in
            if newValue && !storedServerAddress.isEmpty {
                Task {
                    await startMonitoringIfNeeded()
                }
            } else {
                VMMonitorService.shared.stopMonitoring()
            }
        }
        .onChange(of: storedServerAddress) { _, newValue in
            if notificationsEnabled && !newValue.isEmpty {
                Task {
                    await startMonitoringIfNeeded()
                }
            } else if newValue.isEmpty {
                VMMonitorService.shared.stopMonitoring()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            // Restart monitoring when app comes to foreground
            Task {
                await startMonitoringIfNeeded()
            }
        }
    }
    
    private func startMonitoringIfNeeded() async {
        guard notificationsEnabled && !storedServerAddress.isEmpty else {
            return
        }
        
        // Check if we have notification permissions
        let notificationManager = NotificationManager.shared
        let authStatus = await notificationManager.checkAuthorizationStatus()
        
        if authStatus == .authorized {
            VMMonitorService.shared.startMonitoring(serverAddress: storedServerAddress)
        }
    }
}

private struct MissingServerConfigurationView: View {
    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.orange)
                Text("Server not configured")
                    .font(.headline)
                Text("Open Settings → Edit server info to add your Proxmox server.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
        }
        .navigationTitle("Dashboard")
        .navigationBarTitleDisplayMode(.large)
        .navigationBarBackButtonHidden(true)
    }
}

#Preview {
    MainTabView()
}
