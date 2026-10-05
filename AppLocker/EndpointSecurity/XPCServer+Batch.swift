//
//  XPCServer+Batch.swift
//  AppLocker
//
//  Created by AppLocker
//

import Foundation
import OSLog
import AppKit

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

        let reason = String(format: String(localized: "open %d application(s)"), approvedPIDs.count)
        Task { @MainActor [weak self] in
            guard let self else { return }
            let success = (try? await AuthenticationManager.authenticate(reason: reason)) ?? false
            self.isAuthenticatingBatch = false

            if !success && self.isRestartingBatchWithNewApps {
                self.handleBatchAutoReAuthenticateWithNewApps()
                return
            }

            self.isRestartingBatchWithNewApps = false
            let batchApps = self.activeBatchApps
            self.activeBatchApps.removeAll()

            if success {
                let survivingApproved = approvedPIDs.filter { pid in
                    batchApps.contains(where: { $0.pid == pid })
                }
                let survivingRejected = rejectedPIDs.filter { pid in
                    batchApps.contains(where: { $0.pid == pid })
                }
                self.handleBatchSuccess(
                    batchApps: batchApps,
                    approvedPIDs: survivingApproved,
                    rejectedPIDs: survivingRejected
                )
            } else {
                let allPIDs = batchApps.map(\.pid)
                if !allPIDs.isEmpty {
                    Logfile.appXPC.warning(
                        "[Auth] Batch auth failed/cancelled. Rejecting PIDs: \(allPIDs, privacy: .public)"
                    )
                    ESXPCClient.shared.processPendingApps(approvedPIDs: [], rejectedPIDs: allPIDs) { _ in }
                }
            }

            if !self.pendingApps.isEmpty {
                self.processIncomingQueue()
            }
        }
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
        ESXPCClient.shared.processPendingApps(
            approvedPIDs: approvedPIDs,
            rejectedPIDs: rejectedPIDs
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
    func handleCancel() {
        stopCountdownTimer()
        isAuthenticatingSingleApp = false
        isAuthenticatingBatch = false
        isRestartingBatchWithNewApps = false
        BatchAuthWindowController.shared.hideWindow()
        let allPIDs = (pendingApps + activeBatchApps).map(\.pid)
        pendingApps.removeAll()
        activeBatchApps.removeAll()
        if !allPIDs.isEmpty {
            Logfile.appXPC.notice("[Auth] Cancelled by user. Rejecting all PIDs: \(allPIDs, privacy: .public)")
            ESXPCClient.shared.processPendingApps(approvedPIDs: [], rejectedPIDs: allPIDs) { _ in }
        }
    }
}
