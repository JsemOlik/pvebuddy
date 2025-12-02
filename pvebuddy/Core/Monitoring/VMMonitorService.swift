//
//  VMMonitorService.swift
//  pvebuddy
//
//  Created by Oliver Steiner on 01.12.2025.
//

import Foundation
import SwiftUI
import Combine

@MainActor
final class VMMonitorService: ObservableObject {
    static let shared = VMMonitorService()
    
    @Published private(set) var isMonitoring: Bool = false
    
    private var serverAddress: String = ""
    private var client: ProxmoxClient?
    private var monitoringTask: Task<Void, Never>?
    private var previousVMStates: [String: String] = [:] // [vmId: status]
    private let notificationManager = NotificationManager.shared
    
    private init() {}
    
    /// Start monitoring VMs for status changes
    func startMonitoring(serverAddress: String) {
        guard !isMonitoring else {
            print("⚠️ Monitoring already started, skipping")
            return
        }
        
        print("🚀 Starting VM monitoring service...")
        self.serverAddress = serverAddress
        self.client = ProxmoxClient(baseAddress: serverAddress)
        self.isMonitoring = true
        
        // Load initial state
        Task {
            await loadInitialVMStates()
        }
        
        // Start periodic monitoring
        monitoringTask = Task { [weak self] in
            guard let self else { return }
            print("✅ VM monitoring task started")
            while !Task.isCancelled && self.isMonitoring {
                await self.checkVMStates()
                try? await Task.sleep(nanoseconds: 5_000_000_000) // Check every 5 seconds
            }
            print("🛑 VM monitoring task stopped")
        }
    }
    
    /// Stop monitoring VMs
    func stopMonitoring() {
        isMonitoring = false
        monitoringTask?.cancel()
        monitoringTask = nil
        previousVMStates.removeAll()
    }
    
    /// Load initial VM states to establish baseline
    private func loadInitialVMStates() async {
        guard let client = client else { return }
        
        do {
            // Use the lightweight endpoint that doesn't fetch details
            let vmItems = try await client.fetchVMListWithStatuses()
            print("📊 Loading initial VM states for \(vmItems.count) VMs")
            for item in vmItems {
                let key = "\(item.node)_\(item.vmid)"
                let status = item.status.lowercased()
                previousVMStates[key] = status
                print("  - VM \(item.name) (\(item.vmid)): \(status)")
            }
        } catch {
            print("❌ Failed to load initial VM states: \(error)")
        }
    }
    
    /// Check for VM state changes and send notifications
    private func checkVMStates() async {
        guard let client = client else { return }
        
        // Check if notifications are enabled
        let notificationsEnabled = UserDefaults.standard.bool(forKey: "notifications_enabled")
        let notifyStatusChanges = UserDefaults.standard.bool(forKey: "notifications_status_changes")
        
        guard notificationsEnabled && notifyStatusChanges else {
            return
        }
        
        // Check authorization status
        let authStatus = await notificationManager.checkAuthorizationStatus()
        guard authStatus == .authorized else {
            if authStatus != .authorized {
                print("🔔 Notifications not authorized, status: \(authStatus.rawValue)")
            }
            return
        }
        
        do {
            // Use the lightweight endpoint that doesn't fetch details to avoid 500 errors
            let vmItems = try await client.fetchVMListWithStatuses()
            var newStates: [String: String] = [:]
            var vmNames: [String: String] = [:] // Track VM names for notifications
            
            for item in vmItems {
                let key = "\(item.node)_\(item.vmid)"
                let currentStatus = item.status.lowercased()
                newStates[key] = currentStatus
                vmNames[key] = item.name
                
                // Check if this VM was previously running and is now stopped
                if let previousStatus = previousVMStates[key] {
                    // Debug logging
                    if previousStatus != currentStatus {
                        print("🔄 VM \(item.name) (\(item.vmid)) status changed: \(previousStatus) -> \(currentStatus)")
                    }
                    
                    // Proxmox uses various status values - check for power-off transitions
                    let wasRunning = previousStatus == "running"
                    let isStopped = currentStatus == "stopped" || currentStatus == "stopped (locked)"
                    
                    if wasRunning && isStopped {
                        // VM powered off - send notification
                        print("🔔 VM \(item.name) powered off! Sending notification...")
                        notificationManager.notifyVMPoweredOff(vmName: item.name, node: item.node)
                    }
                }
            }
            
            // Check for VMs that were running but are no longer in the list (might have been deleted)
            // We won't notify on deletion, but we should clean up the state
            for (key, previousStatus) in previousVMStates {
                if newStates[key] == nil && previousStatus == "running" {
                    // VM was running but is now gone - might have been deleted
                    // We don't notify on deletion, just clean up
                    print("🗑️ VM \(key) was running but is no longer in the list (possibly deleted)")
                }
            }
            
            // Update previous states
            previousVMStates = newStates
        } catch {
            print("❌ Failed to check VM states: \(error)")
        }
    }
}

