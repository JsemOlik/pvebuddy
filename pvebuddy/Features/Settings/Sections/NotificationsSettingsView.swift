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
    @AppStorage("pve_server_address") private var serverAddress: String = ""
    
    // VM Notifications
    @AppStorage("notifications_vm_power_changes") private var notifyVMPowerChanges: Bool = true
    @AppStorage("notifications_vm_cpu_threshold") private var notifyVMCPUThreshold: Bool = false
    @AppStorage("notifications_vm_ram_threshold") private var notifyVMRAMThreshold: Bool = false
    @AppStorage("notifications_vm_storage_threshold") private var notifyVMStorageThreshold: Bool = false
    
    // LXC Notifications
    @AppStorage("notifications_lxc_power_changes") private var notifyLXCPowerChanges: Bool = false
    @AppStorage("notifications_lxc_cpu_threshold") private var notifyLXCCPUThreshold: Bool = false
    @AppStorage("notifications_lxc_ram_threshold") private var notifyLXCRAMThreshold: Bool = false
    @AppStorage("notifications_lxc_storage_threshold") private var notifyLXCStorageThreshold: Bool = false
    
    // Cluster/Datacenter Notifications
    @AppStorage("notifications_cluster_node_down") private var notifyClusterNodeDown: Bool = false
    @AppStorage("notifications_cluster_low_storage") private var notifyClusterLowStorage: Bool = false
    @AppStorage("notifications_cluster_out_of_ram") private var notifyClusterOutOfRAM: Bool = false
    @AppStorage("notifications_cluster_high_cpu") private var notifyClusterHighCPU: Bool = false
    
    @State private var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @State private var showPermissionAlert: Bool = false
    
    private let notificationManager = NotificationManager.shared

    var body: some View {
        Form {
            // Main Toggle Section
            Section(footer: Text("Enable notifications to receive alerts about your Proxmox cluster. You can fine-tune specific categories below.")) {
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
            }
            
            // Cluster/Datacenter Notifications
            Section(header: Text("Cluster & Datacenter"), footer: Text("Get notified about cluster-wide issues and node health.")) {
                Toggle(isOn: $notifyClusterNodeDown) {
                    Label("Node down", systemImage: "server.rack")
                }
                .disabled(!notificationsEnabled)
                
                Toggle(isOn: $notifyClusterLowStorage) {
                    Label("Low storage on node", systemImage: "externaldrive.trianglebadge.exclamationmark")
                }
                .disabled(!notificationsEnabled)
                
                Toggle(isOn: $notifyClusterOutOfRAM) {
                    Label("Node out of RAM", systemImage: "memorychip")
                }
                .disabled(!notificationsEnabled)
                
                Toggle(isOn: $notifyClusterHighCPU) {
                    Label("High CPU usage on node", systemImage: "cpu")
                }
                .disabled(!notificationsEnabled)
            }
            
            // VM Notifications
            Section(header: Text("Virtual Machines"), footer: Text("Monitor your VMs for power state changes, resource usage, and storage issues.")) {
                Toggle(isOn: $notifyVMPowerChanges) {
                    Label("Power state changes", systemImage: "power")
                }
                .disabled(!notificationsEnabled)
                
                Toggle(isOn: $notifyVMCPUThreshold) {
                    Label("High CPU usage", systemImage: "cpu")
                }
                .disabled(!notificationsEnabled)
                
                Toggle(isOn: $notifyVMRAMThreshold) {
                    Label("High RAM usage", systemImage: "memorychip")
                }
                .disabled(!notificationsEnabled)
                
                Toggle(isOn: $notifyVMStorageThreshold) {
                    Label("Low storage", systemImage: "externaldrive")
                }
                .disabled(!notificationsEnabled)
            }
            
            // LXC Container Notifications
            Section(header: Text("LXC Containers"), footer: Text("Monitor your containers for power state changes, resource usage, and storage issues.")) {
                Toggle(isOn: $notifyLXCPowerChanges) {
                    Label("Power state changes", systemImage: "power")
                }
                .disabled(!notificationsEnabled)
                
                Toggle(isOn: $notifyLXCCPUThreshold) {
                    Label("High CPU usage", systemImage: "cpu")
                }
                .disabled(!notificationsEnabled)
                
                Toggle(isOn: $notifyLXCRAMThreshold) {
                    Label("High RAM usage", systemImage: "memorychip")
                }
                .disabled(!notificationsEnabled)
                
                Toggle(isOn: $notifyLXCStorageThreshold) {
                    Label("Low storage", systemImage: "externaldrive")
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
        .onChange(of: notifyVMPowerChanges) { _, newValue in
            // Update monitoring when VM power changes toggle changes
            if newValue && notificationsEnabled && !serverAddress.isEmpty {
                Task {
                    let authStatus = await notificationManager.checkAuthorizationStatus()
                    if authStatus == .authorized {
                        VMMonitorService.shared.startMonitoring(serverAddress: serverAddress)
                    }
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
            
            // Start monitoring if server address is available and VM power changes are enabled
            if !serverAddress.isEmpty && notifyVMPowerChanges {
                VMMonitorService.shared.startMonitoring(serverAddress: serverAddress)
            }
        } else {
            showPermissionAlert = true
        }
    }
    
    private func checkAuthorizationStatus() async {
        authorizationStatus = await notificationManager.checkAuthorizationStatus()
        
        // If authorized and notifications are enabled, start monitoring
        if authorizationStatus == .authorized && notificationsEnabled && !serverAddress.isEmpty && notifyVMPowerChanges {
            VMMonitorService.shared.startMonitoring(serverAddress: serverAddress)
        }
    }
}

#Preview {
    NavigationStack { NotificationsSettingsView() }
}
