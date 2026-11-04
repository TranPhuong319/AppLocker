//
//  XPCServer+SingleAuth.swift
//  AppLocker
//
//  Created by Doe Phương on 4/11/26.
//

import Foundation
import LocalAuthentication
import os

// MARK: - Single App Authentication Extension

extension XPCServer {
    @MainActor
    func processIncomingQueue() {
        pendingDebounceTask?.cancel()
        pendingDebounceTask = nil
        guard !pendingApps.isEmpty, !isAuthenticating, !dependencies.isBatchWindowVisible() else { return }

        if pendingApps.count == 1 {
            let app = pendingApps[0]
            isAuthenticatingSingleApp = true
            currentSingleAppPID = app.pid

            startSingleAppWatchdog(for: app)

            let reason = String(format: String(localized: "open %@"), app.name)
            Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    let success = try await self.dependencies.authenticate(reason)
                    self.handleSingleAppAuthResult(app: app, success: success, error: nil)
                } catch {
                    self.handleSingleAppAuthResult(app: app, success: false, error: error)
                }
            }
        } else {
            startOrResetCountdownTimer()
            dependencies.onShowBatchWindow()
        }
    }

    @MainActor
    private func startSingleAppWatchdog(for app: PendingAppItem) {
        singleAppWatchdogTask?.cancel()
        let configuredSeconds = dependencies.userDefaults.integer(forKey: "batchAuthCountdownSeconds")
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
            self.dependencies.cancelAuth()

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
            LockES.shared.updateCDHashIfNeeded(for: app.path, cdhash: app.cdhash)
            self.dependencies.onProcessPendingApps(
                [app.pid],
                [],
                AuthDecisionReason.userApprove.rawValue
            )
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
            rejectionReason = AuthDecisionReason.userCancel.rawValue
            Logfile.appXPC.notice(
                """
                [Auth] Cancelled by user. Rejecting PID: \(app.pid, privacy: .public) \
                (\(app.name, privacy: .public))
                """
            )
        } else if let laError = error as? LAError, laError.code == .appCancel {
            rejectionReason = AuthDecisionReason.timeout.rawValue
            Logfile.appXPC.notice(
                """
                [Auth] Watchdog timeout cancelled prompt. Rejecting PID: \(app.pid, privacy: .public) \
                (\(app.name, privacy: .public))
                """
            )
        } else if let error {
            rejectionReason = AuthDecisionReason.userCancel.rawValue
            Logfile.appXPC.error(
                """
                [Auth] Auth failed with error: \(error.localizedDescription, privacy: .public). \
                Rejecting PID: \(app.pid, privacy: .public)
                """
            )
        } else {
            rejectionReason = AuthDecisionReason.timeout.rawValue
            Logfile.appXPC.notice(
                "[Auth] Watchdog timeout forced rejection for PID: \(app.pid, privacy: .public)"
            )
        }
        self.dependencies.onProcessPendingApps(
            [],
            [app.pid],
            rejectionReason
        )
    }

    @MainActor
    private func handleBatchUpgradeAuthResult(app: PendingAppItem, success: Bool) {
        self.isUpgradingToBatch = false
        self.singleAppWatchdogTask?.cancel()
        self.singleAppWatchdogTask = nil
        self.currentSingleAppPID = nil
        if success {
            self.pendingApps.removeAll { $0.id == app.id }
            LockES.shared.updateCDHashIfNeeded(for: app.path, cdhash: app.cdhash)
            self.dependencies.onProcessPendingApps(
                [app.pid],
                [],
                AuthDecisionReason.userApprove.rawValue
            )
        }
        if !self.pendingApps.isEmpty {
            self.processIncomingQueue()
        }
    }
}
