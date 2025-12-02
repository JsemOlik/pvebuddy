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
        guard !isMonitoring else { return }
        
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
            while !Task.isCancelled && self.isMonitoring {
                await self.checkVMStates()
                try? await Task.sleep(nanoseconds: 5_000_000_000) // Check every 5 seconds
            }
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
            let vms = try await client.fetchAllVMs()
            for vm in vms {
                let key = "\(vm.node)_\(vm.vmid)"
                previousVMStates[key] = vm.status.lowercased()
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
            return
        }
        
        do {
            let vms = try await client.fetchAllVMs()
            var newStates: [String: String] = [:]
            
            for vm in vms {
                let key = "\(vm.node)_\(vm.vmid)"
                let currentStatus = vm.status.lowercased()
                newStates[key] = currentStatus
                
                // Check if this VM was previously running and is now stopped
                if let previousStatus = previousVMStates[key],
                   previousStatus == "running" && currentStatus == "stopped" {
                    // VM powered off - send notification
                    notificationManager.notifyVMPoweredOff(vmName: vm.name, node: vm.node)
                }
            }
            
            // Update previous states
            previousVMStates = newStates
            
            // Also check for VMs that disappeared (might have been deleted)
            // We'll keep them in previousVMStates but won't notify on deletion
        } catch {
            print("❌ Failed to check VM states: \(error)")
        }
    }
}

