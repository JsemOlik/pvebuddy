//
//  NotificationsSettitngsView.swift
//  pvebuddy
//
//  Created by Oliver Steiner on 01.12.2025.
//

import SwiftUI
import UserNotifications

struct NotificationsSettingsView: View {
    @AppStorage("notifications_enabled") private var notificationsEnabled: Bool = false
    @AppStorage("notifications_status_changes") private var notifyStatusChanges: Bool = true
    @AppStorage("notifications_storage_threshold") private var notifyStorageThreshold: Bool = true
    @AppStorage("pve_server_address") private var serverAddress: String = ""
    
    @State private var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @State private var showPermissionAlert: Bool = false
    
    private let notificationManager = NotificationManager.shared

    var body: some View {
        Form {
            Section(footer: Text("Manage local notifications from PVE Buddy. You can fine-tune categories as features roll out.")) {
                Toggle(isOn: Binding(
                    get: { notificationsEnabled },
                    set: { newValue in
                        if newValue {
                            Task {
                                await requestPermissionsAndEnable()
                            }
                        } else {
                            notificationsEnabled = false
                            VMMonitorService.shared.stopMonitoring()
                        }
                    }
                )) {
                    Label("Enable notifications", systemImage: "bell")
                }
                .tint(.blue)

                if notificationsEnabled {
                    if authorizationStatus == .denied {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text("Notifications are disabled in Settings")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else if authorizationStatus == .authorized {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("Notifications enabled")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Toggle(isOn: $notifyStatusChanges) {
                    Label("Cluster status changes", systemImage: "bolt.trianglebadge.exclamationmark")
                }
                .disabled(!notificationsEnabled)

                Toggle(isOn: $notifyStorageThreshold) {
                    Label("Low storage threshold", systemImage: "externaldrive.trianglebadge.exclamationmark")
                }
                .disabled(!notificationsEnabled)
            }
        }
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await checkAuthorizationStatus()
        }
        .onChange(of: notificationsEnabled) { _, newValue in
            if newValue {
                Task {
                    await checkAuthorizationStatus()
                }
            }
        }
        .alert("Notification Permission Required", isPresented: $showPermissionAlert) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) {
                notificationsEnabled = false
            }
        } message: {
            Text("Please enable notifications in Settings to receive alerts about VM status changes.")
        }
    }
    
    private func requestPermissionsAndEnable() async {
        let granted = await notificationManager.requestAuthorization()
        if granted {
            notificationsEnabled = true
            await checkAuthorizationStatus()
            
            // Start monitoring if server address is available
            if !serverAddress.isEmpty {
                VMMonitorService.shared.startMonitoring(serverAddress: serverAddress)
            }
        } else {
            showPermissionAlert = true
        }
    }
    
    private func checkAuthorizationStatus() async {
        authorizationStatus = await notificationManager.checkAuthorizationStatus()
        
        // If authorized and notifications are enabled, start monitoring
        if authorizationStatus == .authorized && notificationsEnabled && !serverAddress.isEmpty {
            VMMonitorService.shared.startMonitoring(serverAddress: serverAddress)
        }
    }
}

#Preview {
    NavigationStack { NotificationsSettingsView() }
}
