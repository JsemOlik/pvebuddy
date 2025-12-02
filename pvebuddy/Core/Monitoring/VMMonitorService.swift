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
        // Stop existing monitoring if running
        if isMonitoring {
            print("⚠️ Monitoring already started, restarting...")
            stopMonitoring()
        }
        
        guard !serverAddress.isEmpty else {
            print("❌ Cannot start monitoring: server address is empty")
            return
        }
        
        print("🚀 Starting VM monitoring service for: \(serverAddress)")
        self.serverAddress = serverAddress
        self.client = ProxmoxClient(baseAddress: serverAddress)
        self.isMonitoring = true
        
        // Start periodic monitoring (load initial state first, then start checking)
        monitoringTask = Task { [weak self] in
            guard let self else {
                print("❌ Monitoring task failed: self is nil")
                return
            }
            print("✅ VM monitoring task started")
            
            // Load initial state first before starting periodic checks
            await self.loadInitialVMStates()
            print("📊 Initial states loaded, starting periodic checks...")
            
            var checkCount = 0
            while !Task.isCancelled && self.isMonitoring {
                checkCount += 1
                print("🔍 Running check #\(checkCount)...")
                await self.checkVMStates()
                try? await Task.sleep(nanoseconds: 3_000_000_000) // Check every 3 seconds
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
        
        // Try to load from UserDefaults first (for background task continuity)
        let previousStatesKey = "vm_monitor_previous_states"
        if let data = UserDefaults.standard.data(forKey: previousStatesKey),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            previousVMStates = decoded
            print("📊 Loaded \(previousVMStates.count) previous states from storage")
        }
        
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
            
            // Save to UserDefaults for background tasks
            if let encoded = try? JSONEncoder().encode(previousVMStates) {
                UserDefaults.standard.set(encoded, forKey: previousStatesKey)
            }
        } catch {
            print("❌ Failed to load initial VM states: \(error)")
        }
    }
    
    /// Check for VM state changes and send notifications
    private func checkVMStates() async {
        guard let client = client else {
            print("⚠️ No client available for monitoring")
            return
        }
        
        // Check if notifications are enabled
        let notificationsEnabled = UserDefaults.standard.bool(forKey: "notifications_enabled")
        let notifyStatusChanges = UserDefaults.standard.bool(forKey: "notifications_status_changes")
        
        guard notificationsEnabled && notifyStatusChanges else {
            if !notificationsEnabled {
                print("🔕 Notifications disabled, skipping check")
            } else if !notifyStatusChanges {
                print("🔕 Status change notifications disabled, skipping check")
            }
            return
        }
        
        // Check authorization status
        let authStatus = await notificationManager.checkAuthorizationStatus()
        guard authStatus == .authorized else {
            print("🔔 Notifications not authorized, status: \(authStatus.rawValue)")
            return
        }
        
        print("🔍 Checking VM states... (previous states: \(previousVMStates.count))")
        
        do {
            // Use the lightweight endpoint that doesn't fetch details to avoid 500 errors
            let vmItems = try await client.fetchVMListWithStatuses()
            print("📋 Found \(vmItems.count) VMs in cluster")
            var newStates: [String: String] = [:]
            var vmNames: [String: String] = [:] // Track VM names for notifications
            
            for item in vmItems {
                let key = "\(item.node)_\(item.vmid)"
                let currentStatus = item.status.lowercased()
                newStates[key] = currentStatus
                vmNames[key] = item.name
                
                // Check if this VM was previously running and is now stopped
                if let previousStatus = previousVMStates[key] {
                    // Debug logging for all status changes
                    if previousStatus != currentStatus {
                        print("🔄 VM \(item.name) (\(item.vmid)) status changed: '\(previousStatus)' -> '\(currentStatus)'")
                    }
                    
                    // Proxmox uses various status values - check for power-off transitions
                    // Status can be: "running", "stopped", "stopped (locked)", "paused", "suspended", etc.
                    let wasRunning = previousStatus == "running"
                    let isStopped = currentStatus == "stopped" || 
                                   currentStatus.contains("stopped") ||
                                   currentStatus == "off"
                    
                    print("  - Previous: '\(previousStatus)' (running: \(wasRunning))")
                    print("  - Current: '\(currentStatus)' (stopped: \(isStopped))")
                    
                    if wasRunning && isStopped {
                        // VM powered off - send notification
                        print("🔔 VM \(item.name) powered off! Sending notification...")
                        notificationManager.notifyVMPoweredOff(vmName: item.name, node: item.node)
                    }
                } else {
                    // New VM detected (wasn't in previous states)
                    print("➕ New VM detected: \(item.name) (\(item.vmid)) - \(currentStatus)")
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
            
            // Save to UserDefaults for background tasks
            if let encoded = try? JSONEncoder().encode(previousVMStates) {
                UserDefaults.standard.set(encoded, forKey: "vm_monitor_previous_states")
            }
            
            print("✅ State check complete. Updated states: \(previousVMStates.count)")
        } catch {
            print("❌ Failed to check VM states: \(error)")
        }
    }
}

