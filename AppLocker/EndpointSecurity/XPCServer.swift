//
//  XPCServer.swift
//  AppLocker
//
//  Created by Doe Phương on 27/9/25.
//

import AppKit
import Combine
import Foundation
import os

final class XPCServer: NSObject, ESXPCProtocol, ObservableObject, @unchecked Sendable {
    static let shared = XPCServer()

    @Published var authError: String?
    @Published var pendingApps: [PendingAppItem] = []
    @Published var remainingSeconds: Int = 60

    private var pendingDebounceTimer: Timer?
    private var countdownTimer: Timer?
    private var isAuthenticating: Bool = false
    private var isUpgradingToBatch: Bool = false

    override init() {
        super.init()
    }

    // MARK: - Luồng Phụ (Background XPC Receiver)
    // Extension -> App notification when exec attempted and app suspended for pending verification
    func notifyBlockedExec(name: String, path: String, cdhash: String, pid: Int32) {
        Logfile.core.log(
            """
            Endpoint Security Pending Exec App added:
            Name:   \(name)
            Path:   \(path)
            CDHash: \(cdhash.prefix(8))
            PID:    \(pid)
            """
        )

        DispatchQueue.main.async { [weak self] in
            self?.addPendingAuth(name: name, path: path, cdhash: cdhash, pid: pid)
        }
    }

    // MARK: - Luồng Main Chính (UI State & Batch Auth)

    @MainActor
    func addPendingAuth(name: String, path: String, cdhash: String, pid: Int32) {
        // Deduplicate PID (or path if pid == 0)
        let exists = self.pendingApps.contains { (pid != 0 && $0.pid == pid) || (pid == 0 && $0.path == path) }

        if !exists {
            let item = PendingAppItem(name: name, path: path, cdhash: cdhash, pid: pid, isSelected: true)
            self.pendingApps.append(item)
            Logfile.core.log("XPCServer: Added PID \(pid) (\(name)) to pending queue. Total: \(self.pendingApps.count)")
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
                self.pendingDebounceTimer?.invalidate()
                self.pendingDebounceTimer = nil
                AuthenticationManager.cancelCurrentAuthentication()
            }
            return
        }

        // Debounce for 0.25s for instant response time on single app launches
        self.pendingDebounceTimer?.invalidate()
        self.pendingDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                self?.processIncomingQueue()
            }
        }
    }

    @MainActor
    private func processIncomingQueue() {
        pendingDebounceTimer?.invalidate()
        pendingDebounceTimer = nil

        guard !pendingApps.isEmpty, !isAuthenticating, !BatchAuthWindowController.shared.isWindowVisible else { return }

        if pendingApps.count == 1 {
            // 1 APP: Direct Touch ID without showing BatchAuthWindow
            let app = pendingApps[0]
            isAuthenticating = true

            let reason = String(format: String(localized: "open %@"), app.name)
            AuthenticationManager.authenticate(reason: reason) { [weak self] success, _ in
                DispatchQueue.main.async {
                    guard let self = self else { return }
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
                        Logfile.core.log("SingleAppAuth: Succeeded for \(app.name) (PID: \(app.pid))")
                        ESXPCClient.shared.processPendingApps(approvedPIDs: [app.pid], rejectedPIDs: []) { _ in }
                    } else {
                        Logfile.core.error("SingleAppAuth: Failed/Cancelled for \(app.name) (PID: \(app.pid))")
                        ESXPCClient.shared.processPendingApps(approvedPIDs: [], rejectedPIDs: [app.pid]) { _ in }
                    }

                    if !self.pendingApps.isEmpty {
                        self.processIncomingQueue()
                    }
                }
            }
        } else {
            // 2+ APPS: Show BatchAuthWindow
            startOrResetCountdownTimer()
            BatchAuthWindowController.shared.showWindow()
        }
    }

    @MainActor
    func startOrResetCountdownTimer() {
        countdownTimer?.invalidate()
        remainingSeconds = 60

        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if self.remainingSeconds > 0 {
                    self.remainingSeconds -= 1
                } else {
                    Logfile.core.warning("XPCServer: 60s Timeout reached! Auto cancelling all pending PIDs.")
                    self.handleCancel()
                }
            }
        }
    }

    @MainActor
    func stopCountdownTimer() {
        countdownTimer?.invalidate()
        countdownTimer = nil
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
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isAuthenticating = false

                if success {
                    Logfile.core.log(
                        "XPCServer: Batch auth succeeded. Approved: \(approvedPIDs), Rejected: \(rejectedPIDs)"
                    )
                    ESXPCClient.shared.processPendingApps(
                        approvedPIDs: approvedPIDs,
                        rejectedPIDs: rejectedPIDs
                    ) { _ in }
                } else {
                    let allPIDs = currentApps.map { $0.pid }
                    Logfile.core.error("XPCServer: Batch auth failed or cancelled. Rejecting all PIDs: \(allPIDs)")
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
            Logfile.core.log("XPCServer: Cancelled. Rejecting all PIDs: \(allPIDs)")
            ESXPCClient.shared.processPendingApps(approvedPIDs: [], rejectedPIDs: allPIDs) { _ in }
        }
    }
}
