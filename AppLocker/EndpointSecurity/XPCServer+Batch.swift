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
        isAuthenticating = true
        stopCountdownTimer()
        BatchAuthWindowController.shared.hideWindow()

        let approvedPIDs = pendingApps.filter(\.isSelected).map(\.pid)
        let rejectedPIDs = pendingApps.filter { !$0.isSelected }.map(\.pid)
        let currentApps = pendingApps
        pendingApps.removeAll()

        let reason = String(format: String(localized: "open %d application(s)"), approvedPIDs.count)
        Task { @MainActor [weak self] in
            guard let self else { return }
            let success = (try? await AuthenticationManager.authenticate(reason: reason)) ?? false
            self.isAuthenticating = false

            if success {
                let now = Date()
                currentApps.filter(\.isSelected).forEach { self.lastAuthTimestampsByPath[$0.path] = now }
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
            } else {
                let allPIDs = currentApps.map(\.pid)
                Logfile.appXPC.warning(
                    "[Auth] Batch auth failed/cancelled. Rejecting PIDs: \(allPIDs, privacy: .public)"
                )
                ESXPCClient.shared.processPendingApps(approvedPIDs: [], rejectedPIDs: allPIDs) { _ in }
            }

            if !self.pendingApps.isEmpty {
                self.processIncomingQueue()
            }
        }
    }

    @MainActor
    func handleCancel() {
        stopCountdownTimer()
        isAuthenticating = false
        BatchAuthWindowController.shared.hideWindow()
        let allPIDs = pendingApps.map(\.pid)
        pendingApps.removeAll()
        if !allPIDs.isEmpty {
            Logfile.appXPC.info("[Auth] Cancelled by user. Rejecting all PIDs: \(allPIDs, privacy: .public)")
            ESXPCClient.shared.processPendingApps(approvedPIDs: [], rejectedPIDs: allPIDs) { _ in }
        }
    }
}
