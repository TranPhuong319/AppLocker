//
//  XPCServer+Batch.swift
//  AppLocker
//
//  Created by AppLocker
//

import AppKit
import Foundation
import LocalAuthentication
import OSLog

// MARK: - Batch Authentication & Notifications Extension

extension XPCServer {
    @MainActor
    func startOrResetCountdownTimer() {
        countdownTask?.cancel()
        let configuredSeconds = UserDefaults.standard.integer(forKey: "batchAuthCountdownSeconds")
        remainingSeconds = configuredSeconds > 0 ? configuredSeconds : 30

        let allPIDs = pendingApps.map(\.pid)
        ESXPCClient.shared.refreshPendingWatchdog(pids: allPIDs)

        countdownTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled && self.remainingSeconds > 0 {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { break }
                self.remainingSeconds -= 1
            }
            if !Task.isCancelled && self.remainingSeconds == 0 {
                Logfile.appXPC.warning("[Auth] Timeout reached! Auto cancelling all pending PIDs.")
                self.handleCancel(reason: "Timeout")
            }
        }
    }

    @MainActor
    func stopCountdownTimer() {
        countdownTask?.cancel()
        countdownTask = nil
    }

    @MainActor
    func handleAuthenticate() {
        guard !isAuthenticating else { return }
        isAuthenticatingBatch = true
        isRestartingBatchWithNewApps = false
        stopCountdownTimer()
        BatchAuthWindowController.shared.hideWindow()

        let approvedPIDs = pendingApps.filter(\.isSelected).map(\.pid)
        let rejectedPIDs = pendingApps.filter { !$0.isSelected }.map(\.pid)
        self.activeBatchApps = pendingApps
        pendingApps.removeAll()

        ESXPCClient.shared.refreshPendingWatchdog(pids: approvedPIDs + rejectedPIDs)

        let reason = String(format: String(localized: "open %d application(s)"), approvedPIDs.count)
        Task { @MainActor [weak self] in
            guard let self else { return }
            let success: Bool
            do {
                success = try await AuthenticationManager.authenticate(reason: reason)
            } catch {
                if let laError = error as? LAError, laError.code == .userCancel || laError.code == .appCancel {
                    Logfile.appXPC.notice("[Auth] Batch auth cancelled by user.")
                } else {
                    Logfile.appXPC.error("[Auth] Batch auth error: \(error.localizedDescription, privacy: .public)")
                }
                success = false
            }
            self.isAuthenticatingBatch = false
            self.handleBatchAuthResult(
                success: success,
                approvedPIDs: approvedPIDs,
                rejectedPIDs: rejectedPIDs
            )
        }
    }

    @MainActor
    private func handleBatchAuthResult(
        success: Bool,
        approvedPIDs: [pid_t],
        rejectedPIDs: [pid_t]
    ) {
        if !success && isRestartingBatchWithNewApps {
            handleBatchAutoReAuthenticateWithNewApps()
            return
        }

        isRestartingBatchWithNewApps = false
        let batchApps = activeBatchApps
        activeBatchApps.removeAll()

        if success {
            let survivingApproved = approvedPIDs.filter { pid in
                batchApps.contains(where: { $0.pid == pid })
            }
            let survivingRejected = rejectedPIDs.filter { pid in
                batchApps.contains(where: { $0.pid == pid })
            }
            handleBatchSuccess(
                batchApps: batchApps,
                approvedPIDs: survivingApproved,
                rejectedPIDs: survivingRejected
            )
        } else {
            handleBatchFailure(batchApps: batchApps)
        }

        if !pendingApps.isEmpty {
            processIncomingQueue()
        }
    }

    @MainActor
    private func handleBatchFailure(batchApps: [PendingAppItem], reason: String = "UserCancel") {
        let allPIDs = batchApps.map(\.pid)
        guard !allPIDs.isEmpty else { return }
        Logfile.appXPC.warning(
            """
            [Auth] Batch auth failed/cancelled (\(reason, privacy: .public)). \
            Rejecting PIDs: \(allPIDs, privacy: .public)
            """
        )
        ESXPCClient.shared.processPendingApps(
            approvedPIDs: [],
            rejectedPIDs: allPIDs,
            rejectionReason: reason
        ) { _ in }
    }

    @MainActor
    private func handleBatchSuccess(
        batchApps: [PendingAppItem],
        approvedPIDs: [Int32],
        rejectedPIDs: [Int32]
    ) {
        let now = Date()
        batchApps.filter(\.isSelected).forEach { self.lastAuthTimestampsByPath[$0.path] = now }
        Logfile.appXPC.notice(
            """
            [Auth] Batch OK. Approved: \(approvedPIDs, privacy: .public), \
            Rejected: \(rejectedPIDs, privacy: .public)
            """
        )
        for app in batchApps where app.isSelected && approvedPIDs.contains(app.pid) {
            AppState.shared.manager.updateCDHashIfNeeded(for: app.path, cdhash: app.cdhash)
        }
        ESXPCClient.shared.processPendingApps(
            approvedPIDs: approvedPIDs,
            rejectedPIDs: rejectedPIDs,
            rejectionReason: "UserCancel"
        ) { _ in }
    }

    @MainActor
    private func handleBatchAutoReAuthenticateWithNewApps() {
        self.isRestartingBatchWithNewApps = false
        Logfile.appXPC.notice(
            "[Auth] New app arrived during batch auth. Merging into batch and auto re-authenticating..."
        )
        let existingPIDs = Set(self.pendingApps.map(\.pid))
        let unhandledActive = self.activeBatchApps.filter { !existingPIDs.contains($0.pid) }
        self.pendingApps = unhandledActive + self.pendingApps
        self.activeBatchApps.removeAll()

        for index in 0..<self.pendingApps.count {
            self.pendingApps[index].isSelected = true
        }

        // Delay 250ms for previous LocalAuthentication sheet to fully dismiss, then re-prompt
        Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .milliseconds(250))
            guard !self.isAuthenticating else { return }
            self.handleAuthenticate()
        }
    }

    @MainActor
    func handleCancel(reason: String = "UserCancel") {
        stopCountdownTimer()
        isAuthenticatingSingleApp = false
        isAuthenticatingBatch = false
        isRestartingBatchWithNewApps = false
        BatchAuthWindowController.shared.hideWindow()
        let allPIDs = (pendingApps + activeBatchApps).map(\.pid)
        pendingApps.removeAll()
        activeBatchApps.removeAll()
        if !allPIDs.isEmpty {
            Logfile.appXPC.notice(
                "[Auth] Cancelled (\(reason, privacy: .public)). Rejecting all PIDs: \(allPIDs, privacy: .public)"
            )
            ESXPCClient.shared.processPendingApps(
                approvedPIDs: [],
                rejectedPIDs: allPIDs,
                rejectionReason: reason
            ) { _ in }
        }
    }
}
