//
//  NotificationManager.swift
//  pvebuddy
//
//  Created by Oliver Steiner on 01.12.2025.
//

import Foundation
import UserNotifications

@MainActor
final class NotificationManager {
    static let shared = NotificationManager()
    
    private init() {}
    
    /// Request notification permissions from the user
    func requestAuthorization() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(
                options: [.alert, .sound, .badge]
            )
            return granted
        } catch {
            print("❌ Failed to request notification authorization: \(error)")
            return false
        }
    }
    
    /// Check current authorization status
    func checkAuthorizationStatus() async -> UNAuthorizationStatus {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus
    }
    
    /// Send a notification for a VM power-off event
    func notifyVMPoweredOff(vmName: String, node: String) {
        let content = UNMutableNotificationContent()
        content.title = "VM Powered Off"
        content.body = "\(vmName) on \(node) has powered off"
        content.sound = .default
        content.categoryIdentifier = "VM_STATUS_CHANGE"
        
        // Add user info for potential deep linking
        content.userInfo = [
            "type": "vm_power_off",
            "vmName": vmName,
            "node": node
        ]
        
        let request = UNNotificationRequest(
            identifier: "vm_power_off_\(vmName)_\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil // Immediate notification
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ Failed to send notification: \(error)")
            }
        }
    }
}

