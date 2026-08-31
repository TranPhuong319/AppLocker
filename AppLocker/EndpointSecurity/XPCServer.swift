//
//  XPCServer.swift
//  AppLocker
//
//  Created by Doe Phương on 27/9/25.
//

import Foundation
import Observation
import os
import UserNotifications

@Observable
final class XPCServer: NSObject, ESXPCProtocol, @unchecked Sendable {
    static let shared = XPCServer()
    @MainActor static var lastAuthTimestampsByPath: [String: Date] = [:]

    var authError: String?
    var pendingApps: [PendingAppItem] = []
    var remainingSeconds: Int = 60

    var pendingDebounceTask: Task<Void, Never>?
    var countdownTask: Task<Void, Never>?
    var isAuthenticating: Bool = false
    var isUpgradingToBatch: Bool = false

    override init() {
        super.init()
    }

    // MARK: - Luồng Phụ (Background XPC Receiver)
    // Extension -> App notification when exec attempted and app suspended for pending verification
    func notifyBlockedExec(name: String, path: String, cdhash: String, pid: Int32) {
        Logfile.appXPC.notice(
            """
            [Auth] Pending execution blocked: \
            Name: \(name, privacy: .public), \
            PID: \(pid, privacy: .public), \
            CDHash: \(cdhash.prefix(8), privacy: .public), \
            Path: \(path, privacy: .public)
            """
        )

        Task { @MainActor [weak self] in
            if AppState.shared.manager.isProtectionDisabled {
                Logfile.appXPC.info(
                    """
                    [Auth] Protection is disabled. \
                    Auto-approving PID \(pid, privacy: .public) (\(name, privacy: .public))
                    """
                )
                ESXPCClient.shared.processPendingApps(approvedPIDs: [pid], rejectedPIDs: []) { _ in }
                return
            }
            self?.addPendingAuth(name: name, path: path, cdhash: cdhash, pid: pid)
        }
    }

    func notifyProcessExited(pid: Int32) {
        Task { @MainActor [weak self] in
            self?.removePendingProcess(pid: pid)
        }
    }

    // MARK: - Luồng Main Chính (UI State & Batch Auth)

    @MainActor
    func removePendingProcess(pid: Int32) {
        guard pid > 0 else { return }
        if let idx = self.pendingApps.firstIndex(where: { $0.pid == pid }) {
            let removedApp = self.pendingApps.remove(at: idx)
            Logfile.appXPC.info(
                """
                [Auth] Pending app process exited externally: \(removedApp.name, privacy: .public) \
                (PID: \(pid, privacy: .public)). Removed from queue.
                """
            )

            // If single app Touch ID prompt was for this app and queue is empty, cancel auth
            if self.isAuthenticating && self.pendingApps.isEmpty {
                self.isAuthenticating = false
                AuthenticationManager.cancelCurrentAuthentication()
            }

            // If BatchAuthWindow is open and no apps left, dismiss window
            if self.pendingApps.isEmpty {
                self.countdownTask?.cancel()
                self.countdownTask = nil
                self.pendingDebounceTask?.cancel()
                self.pendingDebounceTask = nil
                BatchAuthWindowController.shared.hideWindow()
            }
        }
    }

    @MainActor
    private func checkGracePeriod(name: String, path: String, pid: Int32) -> Bool {
        let timeoutMinutes = UserDefaults.standard.integer(forKey: "autoLockTimeoutMinutes")
        if timeoutMinutes > 0, let lastAuth = XPCServer.lastAuthTimestampsByPath[path] {
            let elapsed = Date().timeIntervalSince(lastAuth)
            if elapsed < Double(timeoutMinutes * 60) {
                Logfile.appXPC.info(
                    """
                    [Auth] Per-app grace period active \
                    (\(Int(elapsed), privacy: .public)s / \(timeoutMinutes * 60, privacy: .public)s) \
                    for \(name, privacy: .public). Auto-approving PID \(pid, privacy: .public).
                    """
                )
                ESXPCClient.shared.processPendingApps(approvedPIDs: [pid], rejectedPIDs: []) { _ in }
                return true
            }
        } else if timeoutMinutes == -1, XPCServer.lastAuthTimestampsByPath[path] != nil {
            Logfile.appXPC.info(
                """
                [Auth] Per-app grace period active (When System Sleeps) \
                for \(name, privacy: .public). Auto-approving PID \(pid, privacy: .public).
                """
            )
            ESXPCClient.shared.processPendingApps(approvedPIDs: [pid], rejectedPIDs: []) { _ in }
            return true
        }
        return false
    }

    @MainActor
    func addPendingAuth(name: String, path: String, cdhash: String, pid: Int32) {
        if checkGracePeriod(name: name, path: path, pid: pid) {
            return
        }

        // Deduplicate PID (or path if pid == 0)
        let exists = self.pendingApps.contains { (pid != 0 && $0.pid == pid) || (pid == 0 && $0.path == path) }

        if !exists {
            let item = PendingAppItem(name: name, path: path, cdhash: cdhash, pid: pid, isSelected: true)
            self.pendingApps.append(item)
            Logfile.appXPC.debug(
                """
                [Auth] Added PID \(pid, privacy: .public) (\(name, privacy: .public)) \
                to pending queue. Total: \(self.pendingApps.count, privacy: .public)
                """
            )

            let showNotifications = UserDefaults.standard.object(forKey: "showBlockedNotifications") as? Bool ?? true
            if showNotifications {
                sendBlockedNotification(appName: name)
            }
        }

        // If BatchAuthWindow is ALREADY open, update timer
        if BatchAuthWindowController.shared.isWindowVisible {
            self.startOrResetCountdownTimer()
            return
        }

        // If direct SingleApp CoreAuth prompt is currently active:
        if self.isAuthenticating {
            // If 2+ apps are now pending, cancel the single Touch ID prompt and upgrade to BatchAuthWindow!
            if self.pendingApps.count >= 2 {
                self.isUpgradingToBatch = true
                self.pendingDebounceTask?.cancel()
                self.pendingDebounceTask = nil
                AuthenticationManager.cancelCurrentAuthentication()
            }
            return
        }

        // Debounce for 0.25s for instant response time on single app launches
        self.pendingDebounceTask?.cancel()
        self.pendingDebounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            self?.processIncomingQueue()
        }
    }

    @MainActor
    func processIncomingQueue() {
        pendingDebounceTask?.cancel()
        pendingDebounceTask = nil

        guard !pendingApps.isEmpty, !isAuthenticating, !BatchAuthWindowController.shared.isWindowVisible else { return }

        if pendingApps.count == 1 {
            // 1 APP: Direct Touch ID without showing BatchAuthWindow
            let app = pendingApps[0]
            isAuthenticating = true

            let reason = String(format: String(localized: "open %@"), app.name)
            AuthenticationManager.authenticate(reason: reason) { [weak self] success, _ in
                Task { @MainActor [weak self] in
                    self?.handleSingleAppAuthResult(app: app, success: success)
                }
            }
        } else {
            // 2+ APPS: Show BatchAuthWindow
            startOrResetCountdownTimer()
            BatchAuthWindowController.shared.showWindow()
        }
    }

    @MainActor
    private func handleSingleAppAuthResult(app: PendingAppItem, success: Bool) {
        self.isAuthenticating = false

        // If single app Touch ID prompt was invalidated to upgrade to BatchAuthWindow:
        if self.isUpgradingToBatch {
            self.isUpgradingToBatch = false
            if success {
                if let idx = self.pendingApps.firstIndex(where: { $0.id == app.id }) {
                    self.pendingApps.remove(at: idx)
                }
                ESXPCClient.shared.processPendingApps(approvedPIDs: [app.pid], rejectedPIDs: []) { _ in }
            }
            if !self.pendingApps.isEmpty {
                self.processIncomingQueue()
            }
            return
        }

        if let idx = self.pendingApps.firstIndex(where: { $0.id == app.id }) {
            self.pendingApps.remove(at: idx)
        }

        if success {
            XPCServer.lastAuthTimestampsByPath[app.path] = Date()
            Logfile.appXPC.notice(
                """
                [Auth] SingleAppAuth succeeded for \(app.name, privacy: .public) \
                (PID: \(app.pid, privacy: .public))
                """
            )
            ESXPCClient.shared.processPendingApps(approvedPIDs: [app.pid], rejectedPIDs: []) { _ in }
        } else {
            Logfile.appXPC.warning(
                """
                [Auth] SingleAppAuth failed/cancelled for \(app.name, privacy: .public) \
                (PID: \(app.pid, privacy: .public))
                """
            )
            ESXPCClient.shared.processPendingApps(approvedPIDs: [], rejectedPIDs: [app.pid]) { _ in }
        }

        if !self.pendingApps.isEmpty {
            self.processIncomingQueue()
        }
    }
}

// MARK: - Batch Authentication & Notifications Extension

extension XPCServer {
    @MainActor
    func startOrResetCountdownTimer() {
        countdownTask?.cancel()
        let configuredSeconds = UserDefaults.standard.integer(forKey: "batchAuthCountdownSeconds")
        remainingSeconds = configuredSeconds > 0 ? configuredSeconds : 30

        countdownTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled && self.remainingSeconds > 0 {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { break }
                self.remainingSeconds -= 1
            }
            if !Task.isCancelled && self.remainingSeconds == 0 {
                Logfile.appXPC.warning("[Auth] Timeout reached! Auto cancelling all pending PIDs.")
                self.handleCancel()
            }
        }
    }

    func sendBlockedNotification(appName: String) {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Application Lock")
        content.body = String(format: String(localized: "%@ has been blocked from launching."), appName)
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "BlockedAppNotification-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    @MainActor
    func stopCountdownTimer() {
        countdownTask?.cancel()
        countdownTask = nil
    }

    @MainActor
    func handleAuthenticate() {
        guard !isAuthenticating else { return }
        isAuthenticating = true
        stopCountdownTimer()

        BatchAuthWindowController.shared.hideWindow()

        let approvedPIDs = pendingApps.filter { $0.isSelected }.map { $0.pid }
        let rejectedPIDs = pendingApps.filter { !$0.isSelected }.map { $0.pid }
        let currentApps = pendingApps
        pendingApps.removeAll()

        let reason = String(format: String(localized: "open %d application(s)"), approvedPIDs.count)

        AuthenticationManager.authenticate(reason: reason) { [weak self] success, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isAuthenticating = false

                if success {
                    let now = Date()
                    for item in currentApps where item.isSelected {
                        XPCServer.lastAuthTimestampsByPath[item.path] = now
                    }
                    Logfile.appXPC.notice(
                        """
                        [Auth] Batch auth succeeded. Approved: \(approvedPIDs, privacy: .public), \
                        Rejected: \(rejectedPIDs, privacy: .public)
                        """
                    )
                    ESXPCClient.shared.processPendingApps(
                        approvedPIDs: approvedPIDs,
                        rejectedPIDs: rejectedPIDs
                    ) { _ in }
                } else {
                    let allPIDs = currentApps.map { $0.pid }
                    Logfile.appXPC.warning(
                        "[Auth] Batch auth failed or cancelled. Rejecting all PIDs: \(allPIDs, privacy: .public)"
                    )
                    ESXPCClient.shared.processPendingApps(approvedPIDs: [], rejectedPIDs: allPIDs) { _ in }
                }

                if !self.pendingApps.isEmpty {
                    self.processIncomingQueue()
                }
            }
        }
    }

    @MainActor
    func handleCancel() {
        stopCountdownTimer()
        isAuthenticating = false
        BatchAuthWindowController.shared.hideWindow()

        let allPIDs = pendingApps.map { $0.pid }
        pendingApps.removeAll()

        if !allPIDs.isEmpty {
            Logfile.appXPC.info("[Auth] Cancelled by user. Rejecting all PIDs: \(allPIDs, privacy: .public)")
            ESXPCClient.shared.processPendingApps(approvedPIDs: [], rejectedPIDs: allPIDs) { _ in }
        }
    }
}
