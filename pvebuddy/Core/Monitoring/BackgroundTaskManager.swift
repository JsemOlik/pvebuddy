//
//  BackgroundTaskManager.swift
//  pvebuddy
//
//  Created by Oliver Steiner on 01.12.2025.
//

import Foundation
import BackgroundTasks
import UIKit

@MainActor
final class BackgroundTaskManager {
    static let shared = BackgroundTaskManager()
    
    private let taskIdentifier = "dev.jsemolik.pvebuddy.vm-monitoring"
    
    private init() {}
    
    /// Register background task
    func registerBackgroundTask() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: taskIdentifier,
            using: nil
        ) { [weak self] task in
            guard let self = self else {
                task.setTaskCompleted(success: false)
                return
            }
            self.handleBackgroundTask(task: task as! BGAppRefreshTask)
        }
    }
    
    /// Schedule next background task
    func scheduleBackgroundTask() {
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 3 * 60) // 3 minutes from now
        
        do {
            try BGTaskScheduler.shared.submit(request)
            print("📅 Background task scheduled for 3 minutes from now")
        } catch {
            print("❌ Failed to schedule background task: \(error)")
        }
    }
    
    /// Handle background task execution
    private func handleBackgroundTask(task: BGAppRefreshTask) {
        print("🔄 Background task started")
        
        // Schedule next background task
        scheduleBackgroundTask()
        
        // Set expiration handler
        task.expirationHandler = {
            print("⏰ Background task expired")
            task.setTaskCompleted(success: false)
        }
        
        // Perform monitoring check
        Task { @MainActor in
            let notificationsEnabled = UserDefaults.standard.bool(forKey: "notifications_enabled")
            let notifyStatusChanges = UserDefaults.standard.bool(forKey: "notifications_status_changes")
            let serverAddress = UserDefaults.standard.string(forKey: "pve_server_address") ?? ""
            
            guard notificationsEnabled && notifyStatusChanges && !serverAddress.isEmpty else {
                print("⚠️ Background monitoring skipped: settings not enabled")
                task.setTaskCompleted(success: true)
                return
            }
            
            // Check authorization
            let authStatus = await NotificationManager.shared.checkAuthorizationStatus()
            guard authStatus == .authorized else {
                print("⚠️ Background monitoring skipped: notifications not authorized")
                task.setTaskCompleted(success: true)
                return
            }
            
            // Perform a single check
            await performBackgroundCheck(serverAddress: serverAddress)
            
            task.setTaskCompleted(success: true)
            print("✅ Background task completed")
        }
    }
    
    /// Perform a single monitoring check in background
    private func performBackgroundCheck(serverAddress: String) async {
        let client = ProxmoxClient(baseAddress: serverAddress)
        let notificationManager = NotificationManager.shared
        
        // Load previous states from UserDefaults
        let previousStatesKey = "vm_monitor_previous_states"
        var previousVMStates: [String: String] = [:]
        if let data = UserDefaults.standard.data(forKey: previousStatesKey),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            previousVMStates = decoded
        }
        
        do {
            let vmItems = try await client.fetchVMListWithStatuses()
            var newStates: [String: String] = [:]
            
            for item in vmItems {
                let key = "\(item.node)_\(item.vmid)"
                let currentStatus = item.status.lowercased()
                newStates[key] = currentStatus
                
                // Check for power-off transitions
                if let previousStatus = previousVMStates[key] {
                    let wasRunning = previousStatus == "running"
                    let isStopped = currentStatus == "stopped" || 
                                   currentStatus.contains("stopped") ||
                                   currentStatus == "off"
                    
                    if wasRunning && isStopped {
                        print("🔔 Background: VM \(item.name) powered off!")
                        notificationManager.notifyVMPoweredOff(vmName: item.name, node: item.node)
                    }
                }
            }
            
            // Save new states
            if let encoded = try? JSONEncoder().encode(newStates) {
                UserDefaults.standard.set(encoded, forKey: previousStatesKey)
            }
        } catch {
            print("❌ Background check failed: \(error)")
        }
    }
}

