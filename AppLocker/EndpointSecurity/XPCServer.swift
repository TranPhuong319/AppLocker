//
//  XPCServer.swift
//  AppLocker
//
//  Created by Doe Phương on 27/9/25.
//

import AppKit
import Foundation
import Observation
import os

@Observable
final class XPCServer: NSObject, ESXPCProtocol, @unchecked Sendable {
    static let shared = XPCServer()
    @MainActor var lastAuthTimestampsByPath: [String: Date] = [:]

    var authError: String?
    var pendingApps: [PendingAppItem] = []
    var remainingSeconds: Int = 60
    var pendingDebounceTask: Task<Void, Never>?
    var countdownTask: Task<Void, Never>?
    var isAuthenticating: Bool = false
    var isUpgradingToBatch: Bool = false

    override init() { super.init() }

    // MARK: - Luồng Phụ (Background XPC Receiver)
    // Extension -> App notification when exec attempted and app suspended for pending verification
    nonisolated func notifyBlockedExec(name: String, path: String, cdhash: String, pid: Int32) {
        Logfile.appXPC.notice(
            "[Auth] Blocked: \(name, privacy: .public), PID: \(pid, privacy: .public), Path: \(path, privacy: .public)"
        )

        Task { @MainActor in
            if AppState.shared.manager.isProtectionDisabled {
                Logfile.appXPC.info(
                    "[Auth] Protection disabled. Approving PID \(pid, privacy: .public) (\(name, privacy: .public))"
                )
                ESXPCClient.shared.processPendingApps(approvedPIDs: [pid], rejectedPIDs: []) { _ in }
                return
            }
            XPCServer.shared.addPendingAuth(name: name, path: path, cdhash: cdhash, pid: pid)
        }
    }

    nonisolated func notifyProcessExited(pid: Int32) {
        Task { @MainActor in
            XPCServer.shared.removePendingProcess(pid: pid)
        }
    }

    // MARK: - Luồng Main Chính (UI State & Batch Auth)

    @MainActor
    func removePendingProcess(pid: Int32) {
        guard pid > 0 else { return }
        if let idx = self.pendingApps.firstIndex(where: { $0.pid == pid }) {
            let removedApp = self.pendingApps.remove(at: idx)
            Logfile.appXPC.info(
                "[Auth] Process exited: \(removedApp.name, privacy: .public) (PID: \(pid, privacy: .public))."
            )

            // If single app Touch ID prompt was for this app and queue is empty, cancel auth
            if self.isAuthenticating && self.pendingApps.isEmpty {
                self.isAuthenticating = false
                AuthenticationManager.cancelCurrentAuthentication()
            }

            // If BatchAuthWindow is open and no apps left, dismiss window
            if self.pendingApps.isEmpty {
                self.stopCountdownTimer()
                self.pendingDebounceTask?.cancel()
                self.pendingDebounceTask = nil
                BatchAuthWindowController.shared.hideWindow()
            }
        }
    }

    @MainActor
    private func checkGracePeriod(name: String, path: String, pid: Int32) -> Bool {
        let timeoutMinutes = AppState.shared.manager.autoLockTimeoutMinutes
        if timeoutMinutes > 0, let lastAuth = self.lastAuthTimestampsByPath[path] {
            let elapsed = Date().timeIntervalSince(lastAuth)
            if elapsed < Double(timeoutMinutes * 60) {
                Logfile.appXPC.info(
                    "[Auth] Grace period active (\(Int(elapsed))s) for \(name, privacy: .public). Auto-approving."
                )
                ESXPCClient.shared.processPendingApps(approvedPIDs: [pid], rejectedPIDs: []) { _ in }
                return true
            }
        } else if timeoutMinutes == -1, self.lastAuthTimestampsByPath[path] != nil {
            Logfile.appXPC.info(
                "[Auth] Grace period active (Sleep) for \(name, privacy: .public). Auto-approving."
            )
            ESXPCClient.shared.processPendingApps(approvedPIDs: [pid], rejectedPIDs: []) { _ in }
            return true
        }
        return false
    }

    @MainActor
    func addPendingAuth(name: String, path: String, cdhash: String, pid: Int32) {
        guard !checkGracePeriod(name: name, path: path, pid: pid) else { return }

        // Deduplicate PID (or path if pid == 0)
        let exists = self.pendingApps.contains { (pid != 0 && $0.pid == pid) || (pid == 0 && $0.path == path) }

        if !exists {
            let item = PendingAppItem(name: name, path: path, cdhash: cdhash, pid: pid, isSelected: true)
            self.pendingApps.append(item)
            Logfile.appXPC.debug(
                """
                [Auth] Added PID \(pid, privacy: .public) (\(name, privacy: .public)) \
                to queue (\(self.pendingApps.count))
                """
            )

            let showNotifications = UserDefaults.standard.object(forKey: "showBlockedNotifications") as? Bool ?? true
            if showNotifications {
                NSApp.appDelegate?.sendBlockedNotification(appName: name)
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
            let app = pendingApps[0]
            isAuthenticating = true

            let reason = String(format: String(localized: "open %@"), app.name)
            Task { @MainActor [weak self] in
                guard let self else { return }
                let success = (try? await AuthenticationManager.authenticate(reason: reason)) ?? false
                self.handleSingleAppAuthResult(app: app, success: success)
            }
        } else {
            startOrResetCountdownTimer()
            BatchAuthWindowController.shared.showWindow()
        }
    }

    @MainActor
    private func handleSingleAppAuthResult(app: PendingAppItem, success: Bool) {
        self.isAuthenticating = false
        if self.isUpgradingToBatch {
            handleBatchUpgradeAuthResult(app: app, success: success)
            return
        }

        self.pendingApps.removeAll { $0.id == app.id }

        if success {
            self.lastAuthTimestampsByPath[app.path] = Date()
            Logfile.appXPC.notice(
                "[Auth] Auth OK for \(app.name, privacy: .public) (PID: \(app.pid, privacy: .public))"
            )
            ESXPCClient.shared.processPendingApps(approvedPIDs: [app.pid], rejectedPIDs: []) { _ in }
        } else {
            Logfile.appXPC.warning(
                "[Auth] Auth failed for \(app.name, privacy: .public) (PID: \(app.pid, privacy: .public))"
            )
            ESXPCClient.shared.processPendingApps(approvedPIDs: [], rejectedPIDs: [app.pid]) { _ in }
        }

        if !self.pendingApps.isEmpty {
            self.processIncomingQueue()
        }
    }

    @MainActor
    private func handleBatchUpgradeAuthResult(app: PendingAppItem, success: Bool) {
        self.isUpgradingToBatch = false
        if success {
            self.pendingApps.removeAll { $0.id == app.id }
            ESXPCClient.shared.processPendingApps(approvedPIDs: [app.pid], rejectedPIDs: []) { _ in }
        }
        if !self.pendingApps.isEmpty {
            self.processIncomingQueue()
        }
    }
}
