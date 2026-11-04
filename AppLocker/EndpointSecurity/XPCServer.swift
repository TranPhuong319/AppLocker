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

struct PendingAppItem: Identifiable, Hashable, Sendable {
    let id = UUID()
    let name: String
    let path: String
    let cdhash: String
    let pid: Int32
    var isSelected: Bool = true
}

struct XPCServerDependencies: @unchecked Sendable {
    var userDefaults: UserDefaults = .standard
    var authenticate: @MainActor (String) async throws -> Bool = {
        try await AuthenticationManager.authenticate(reason: $0)
    }
    var cancelAuth: @MainActor () -> Void = {
        AuthenticationManager.cancelCurrentAuthentication()
    }
    var onProcessPendingApps: @MainActor ([Int32], [Int32], String) -> Void = {
        ESXPCClient.shared.processPendingApps(approvedPIDs: $0, rejectedPIDs: $1, rejectionReason: $2) { _ in }
    }
    var onRefreshWatchdog: @MainActor ([Int32]) -> Void = {
        ESXPCClient.shared.refreshPendingWatchdog(pids: $0)
    }
    #if TESTING
    var isBatchWindowVisible: @MainActor () -> Bool = { false }
    var onShowBatchWindow: @MainActor () -> Void = {}
    var onHideBatchWindow: @MainActor () -> Void = {}
    var onSendBlockedNotification: @MainActor (String) -> Void = { _ in }
    #else
    var isBatchWindowVisible: @MainActor () -> Bool = {
        BatchAuthWindowController.shared.isWindowVisible
    }
    var onShowBatchWindow: @MainActor () -> Void = {
        BatchAuthWindowController.shared.showWindow()
    }
    var onHideBatchWindow: @MainActor () -> Void = {
        BatchAuthWindowController.shared.hideWindow()
    }
    var onSendBlockedNotification: @MainActor (String) -> Void = {
        NSApp.appDelegate?.sendBlockedNotification(appName: $0)
    }
    #endif
}

@Observable
@MainActor
final class XPCServer: NSObject, ESXPCProtocol {
    nonisolated static let shared = XPCServer()
    var lastAuthTimestampsByPath: [String: Date] = [:]

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

    @ObservationIgnored var dependencies = XPCServerDependencies()

    nonisolated override init() { super.init() }

    // MARK: - Luồng Phụ (Background XPC Receiver)
    // Extension -> App notification when exec attempted and app suspended for pending verification
    nonisolated func notifyBlockedExec(name: String, path: String, cdhash: String, pid: Int32) {
        Logfile.appXPC.notice(
            "[Auth] Blocked: \(name, privacy: .public), PID: \(pid, privacy: .public), Path: \(path, privacy: .public)"
        )

        Task { @MainActor in
            if LockES.shared.isProtectionDisabled {
                Logfile.appXPC.info(
                    "[Auth] Protection disabled. Approving PID \(pid, privacy: .public) (\(name, privacy: .public))"
                )
                self.dependencies.onProcessPendingApps([pid], [], AuthDecisionReason.userApprove.rawValue)
                return
            }
            self.addPendingAuth(name: name, path: path, cdhash: cdhash, pid: pid)
        }
    }

    nonisolated func notifyProcessExited(pid: Int32) {
        Task { @MainActor in
            self.removePendingProcess(pid: pid)
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
            self.dependencies.cancelAuth()
        }

        // If all pending and active batch apps are gone, cancel any active Touch ID prompt and hide window
        if self.pendingApps.isEmpty && self.activeBatchApps.isEmpty {
            if self.isAuthenticatingBatch {
                Logfile.appXPC.info("[Auth] All batch processes exited. Cancelling active authentication.")
                self.isAuthenticatingBatch = false
                self.isRestartingBatchWithNewApps = false
                self.dependencies.cancelAuth()
            }
            self.stopCountdownTimer()
            self.pendingDebounceTask?.cancel()
            self.pendingDebounceTask = nil
            self.dependencies.onHideBatchWindow()
        }
    }

    @MainActor
    private func pruneExpiredGracePeriodEntries() {
        let timeoutMinutes = LockES.shared.autoLockTimeoutMinutes
        guard timeoutMinutes > 0 else { return }
        let cutoff = Date().addingTimeInterval(-Double(timeoutMinutes * 60))
        self.lastAuthTimestampsByPath = self.lastAuthTimestampsByPath.filter { $0.value > cutoff }
    }

    @MainActor
    private func checkGracePeriod(name: String, path: String, pid: Int32) -> Bool {
        pruneExpiredGracePeriodEntries()
        let timeoutMinutes = LockES.shared.autoLockTimeoutMinutes
        if timeoutMinutes > 0, let lastAuth = self.lastAuthTimestampsByPath[path] {
            let elapsed = Date().timeIntervalSince(lastAuth)
            if elapsed < Double(timeoutMinutes * 60) {
                Logfile.appXPC.info(
                    "[Auth] Grace period active (\(Int(elapsed))s) for \(name, privacy: .public). Auto-approving."
                )
                self.dependencies.onProcessPendingApps([pid], [], AuthDecisionReason.userApprove.rawValue)
                return true
            }
        } else if timeoutMinutes == -1, self.lastAuthTimestampsByPath[path] != nil {
            Logfile.appXPC.info(
                "[Auth] Grace period active (Sleep) for \(name, privacy: .public). Auto-approving."
            )
            self.dependencies.onProcessPendingApps([pid], [], AuthDecisionReason.userApprove.rawValue)
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

            let showNotifications = dependencies.userDefaults.object(forKey: "showBlockedNotifications") as? Bool
                ?? true
            if showNotifications {
                dependencies.onSendBlockedNotification(name)
            }
        }

        // If BatchAuthWindow is ALREADY open, update timer
        if dependencies.isBatchWindowVisible() {
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
            self.dependencies.cancelAuth()
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
                self.dependencies.cancelAuth()
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
