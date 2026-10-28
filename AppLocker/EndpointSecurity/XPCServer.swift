//
//  XPCServer.swift
//  AppLocker
//
//  Created by Doe Phương on 27/9/25.
//

import AppKit
import Foundation
import LocalAuthentication
import Observation
import os

@Observable
final class XPCServer: NSObject, ESXPCProtocol, @unchecked Sendable {
    static let shared = XPCServer()
    @MainActor var lastAuthTimestampsByPath: [String: Date] = [:]

    var authError: String?
    var pendingApps: [PendingAppItem] = []
    var activeBatchApps: [PendingAppItem] = []
    var remainingSeconds: Int = 60
    var pendingDebounceTask: Task<Void, Never>?
    var countdownTask: Task<Void, Never>?
    var singleAppWatchdogTask: Task<Void, Never>?
    var currentSingleAppPID: Int32?
    var isAuthenticatingSingleApp: Bool = false
    var isAuthenticatingBatch: Bool = false
    var isAuthenticating: Bool { isAuthenticatingSingleApp || isAuthenticatingBatch }
    var isUpgradingToBatch: Bool = false
    var isRestartingBatchWithNewApps: Bool = false

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
        let removedBatchApp = self.activeBatchApps.first(where: { $0.pid == pid })
        self.activeBatchApps.removeAll { $0.pid == pid }

        let removedPendingApp: PendingAppItem? = {
            if let idx = self.pendingApps.firstIndex(where: { $0.pid == pid }) {
                return self.pendingApps.remove(at: idx)
            }
            return nil
        }()

        if let app = removedBatchApp ?? removedPendingApp {
            Logfile.appXPC.info(
                "[Auth] Process exited: \(app.name, privacy: .public) (PID: \(pid, privacy: .public))."
            )
        }

        // If single app Touch ID prompt was for this app, cancel auth immediately
        if self.isAuthenticatingSingleApp && (self.currentSingleAppPID == pid || self.pendingApps.isEmpty) {
            Logfile.appXPC.notice(
                """
                [Auth] Pending process (PID: \(pid, privacy: .public)) exited or terminated while \
                single app prompt was active. Cancelling LAContext immediately.
                """
            )
            self.singleAppWatchdogTask?.cancel()
            self.singleAppWatchdogTask = nil
            self.currentSingleAppPID = nil
            self.isAuthenticatingSingleApp = false
            AuthenticationManager.cancelCurrentAuthentication()
        }

        // If all pending and active batch apps are gone, cancel any active Touch ID prompt and hide window
        if self.pendingApps.isEmpty && self.activeBatchApps.isEmpty {
            if self.isAuthenticatingBatch {
                Logfile.appXPC.info("[Auth] All batch processes exited. Cancelling active authentication.")
                self.isAuthenticatingBatch = false
                self.isRestartingBatchWithNewApps = false
                AuthenticationManager.cancelCurrentAuthentication()
            }
            self.stopCountdownTimer()
            self.pendingDebounceTask?.cancel()
            self.pendingDebounceTask = nil
            BatchAuthWindowController.shared.hideWindow()
        }
    }

    @MainActor
    private func pruneExpiredGracePeriodEntries() {
        let timeoutMinutes = AppState.shared.manager.autoLockTimeoutMinutes
        guard timeoutMinutes > 0 else { return }
        let cutoff = Date().addingTimeInterval(-Double(timeoutMinutes * 60))
        self.lastAuthTimestampsByPath = self.lastAuthTimestampsByPath.filter { $0.value > cutoff }
    }

    @MainActor
    private func checkGracePeriod(name: String, path: String, pid: Int32) -> Bool {
        pruneExpiredGracePeriodEntries()
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

        // If Batch Touch ID evaluation is actively underway:
        // Cancel current LAContext to auto re-authenticate with the combined batch
        if self.isAuthenticatingBatch {
            Logfile.appXPC.notice(
                """
                [Auth] New app \(name, privacy: .public) (PID \(pid, privacy: .public)) arrived \
                during batch auth. Adding to batch and re-authenticating...
                """
            )
            self.isRestartingBatchWithNewApps = true
            AuthenticationManager.cancelCurrentAuthentication()
            return
        }

        // If direct SingleApp CoreAuth prompt is currently active:
        if self.isAuthenticatingSingleApp {
            // If 2+ apps are now pending, cancel the single Touch ID prompt and upgrade to BatchAuthWindow!
            if self.pendingApps.count >= 2 {
                self.isUpgradingToBatch = true
                self.pendingDebounceTask?.cancel()
                self.pendingDebounceTask = nil
                self.singleAppWatchdogTask?.cancel()
                self.singleAppWatchdogTask = nil
                self.currentSingleAppPID = nil
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
}

// MARK: - Single App Authentication Extension

extension XPCServer {
    @MainActor
    func processIncomingQueue() {
        pendingDebounceTask?.cancel()
        pendingDebounceTask = nil
        guard !pendingApps.isEmpty, !isAuthenticating, !BatchAuthWindowController.shared.isWindowVisible else { return }

        if pendingApps.count == 1 {
            let app = pendingApps[0]
            isAuthenticatingSingleApp = true
            currentSingleAppPID = app.pid

            startSingleAppWatchdog(for: app)

            let reason = String(format: String(localized: "open %@"), app.name)
            Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    let success = try await AuthenticationManager.authenticate(reason: reason)
                    self.handleSingleAppAuthResult(app: app, success: success, error: nil)
                } catch {
                    self.handleSingleAppAuthResult(app: app, success: false, error: error)
                }
            }
        } else {
            startOrResetCountdownTimer()
            BatchAuthWindowController.shared.showWindow()
        }
    }

    @MainActor
    private func startSingleAppWatchdog(for app: PendingAppItem) {
        singleAppWatchdogTask?.cancel()
        let configuredSeconds = UserDefaults.standard.integer(forKey: "batchAuthCountdownSeconds")
        let timeoutSeconds: Double = configuredSeconds > 0 ? Double(configuredSeconds) : 30.0

        singleAppWatchdogTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(timeoutSeconds))
            guard !Task.isCancelled,
                  let self,
                  self.isAuthenticatingSingleApp,
                  self.currentSingleAppPID == app.pid else {
                return
            }
            Logfile.appXPC.warning(
                """
                [Auth] Single app watchdog timeout (\(timeoutSeconds)s) reached for \
                \(app.name, privacy: .public) (PID \(app.pid, privacy: .public)). \
                Cancelling LAContext to release suspended process.
                """
            )
            AuthenticationManager.cancelCurrentAuthentication()

            // Safety fallback: If LAContext doesn't resume within 2 seconds, force rejection
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled,
                  self.isAuthenticatingSingleApp,
                  self.currentSingleAppPID == app.pid else {
                return
            }
            Logfile.appXPC.error(
                "[Auth] LAContext did not resume continuation in time. Force rejecting PID: \(app.pid)"
            )
            self.handleSingleAppAuthResult(app: app, success: false, error: nil)
        }
    }

    @MainActor
    private func handleSingleAppAuthResult(app: PendingAppItem, success: Bool, error: Error? = nil) {
        self.singleAppWatchdogTask?.cancel()
        self.singleAppWatchdogTask = nil
        self.currentSingleAppPID = nil
        self.isAuthenticatingSingleApp = false
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
            AppState.shared.manager.updateCDHashIfNeeded(for: app.path, cdhash: app.cdhash)
            ESXPCClient.shared.processPendingApps(approvedPIDs: [app.pid], rejectedPIDs: []) { _ in }
        } else {
            handleSingleAppRejection(app: app, error: error)
        }

        if !self.pendingApps.isEmpty {
            self.processIncomingQueue()
        }
    }

    @MainActor
    private func handleSingleAppRejection(app: PendingAppItem, error: Error?) {
        let rejectionReason: String
        if let laError = error as? LAError, laError.code == .userCancel {
            rejectionReason = "UserCancel"
            Logfile.appXPC.notice(
                """
                [Auth] Cancelled by user. Rejecting PID: \(app.pid, privacy: .public) \
                (\(app.name, privacy: .public))
                """
            )
        } else if let laError = error as? LAError, laError.code == .appCancel {
            rejectionReason = "Timeout"
            Logfile.appXPC.notice(
                """
                [Auth] Watchdog timeout cancelled prompt. Rejecting PID: \(app.pid, privacy: .public) \
                (\(app.name, privacy: .public))
                """
            )
        } else if let error {
            rejectionReason = "UserCancel"
            Logfile.appXPC.error(
                """
                [Auth] Auth failed with error: \(error.localizedDescription, privacy: .public). \
                Rejecting PID: \(app.pid, privacy: .public)
                """
            )
        } else {
            rejectionReason = "Timeout"
            Logfile.appXPC.notice(
                "[Auth] Watchdog timeout forced rejection for PID: \(app.pid, privacy: .public)"
            )
        }
        ESXPCClient.shared.processPendingApps(
            approvedPIDs: [],
            rejectedPIDs: [app.pid],
            rejectionReason: rejectionReason
        ) { _ in }
    }

    @MainActor
    private func handleBatchUpgradeAuthResult(app: PendingAppItem, success: Bool) {
        self.isUpgradingToBatch = false
        self.singleAppWatchdogTask?.cancel()
        self.singleAppWatchdogTask = nil
        self.currentSingleAppPID = nil
        if success {
            self.pendingApps.removeAll { $0.id == app.id }
            AppState.shared.manager.updateCDHashIfNeeded(for: app.path, cdhash: app.cdhash)
            ESXPCClient.shared.processPendingApps(approvedPIDs: [app.pid], rejectedPIDs: []) { _ in }
        }
        if !self.pendingApps.isEmpty {
            self.processIncomingQueue()
        }
    }
}
