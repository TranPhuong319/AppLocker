//
//  LockES.swift
//  AppLocker
//
//  Created by Doe Phương on 27/9/25.
//

import AppKit
import Foundation
import Observation

extension Notification.Name {
    static let lockedAppsDidChange = Notification.Name("lockedAppsDidChange")
    static let protectionStatusDidChange = Notification.Name("protectionStatusDidChange")
}

@Observable
@MainActor
class LockES {
    static let shared = LockES()

    var lockedApps: [String: LockedAppConfig] = [:]  // keyed by path
    var allApps: [InstalledApp] = []
    var isProtectionDisabled: Bool = false
    var allowIncomingCalls: Bool = true
    var autoLockTimeoutMinutes: Int = 0

    @ObservationIgnored
    var cdhashScanTask: Task<Void, Never>?
    @ObservationIgnored
    var cdhashPeriodicTask: Task<Void, Never>?

    var onConfigUpdated: (() -> Void)?

    init() {
        // Defer loading to bootstrap() to allow ES Handshake first
    }

    deinit {
        cdhashScanTask?.cancel()
        cdhashPeriodicTask?.cancel()
    }

    func bootstrap(onUpdate: (() -> Void)? = nil) {
        if let onUpdate = onUpdate {
            self.onConfigUpdated = onUpdate
        }
        ConfigStore.shared.performHandshake { [weak self] success in
            guard let self else { return }
            Logfile.policy.info(
                "[LockES] ES Handshake finished (success=\(success, privacy: .public)). Proceeding to load config."
            )

            // Safe to load config now (we are Muted or Launcher mode)
            let loaded = ConfigStore.shared.load()

            Task { @MainActor [weak self] in
                guard let self else { return }
                self.lockedApps = loaded.apps
                self.isProtectionDisabled = loaded.isDisabled
                self.allowIncomingCalls = loaded.allowIncomingCalls
                self.autoLockTimeoutMinutes = loaded.autoLockTimeoutMinutes
                self.setupPeriodicCDHashScan()
                self.verifyAndHealLockedCDHashes()
                // Notify menubar to re-render with the real loaded state
                NotificationCenter.default.post(name: .protectionStatusDidChange, object: nil)
                NotificationCenter.default.post(name: .lockedAppsDidChange, object: nil)
                self.onConfigUpdated?()
            }
        }
    }

    // MARK: - Persistence Helper
    func save() {
        ConfigStore.shared.save(
            apps: self.lockedApps,
            isDisabled: self.isProtectionDisabled,
            allowIncomingCalls: self.allowIncomingCalls,
            autoLockTimeoutMinutes: self.autoLockTimeoutMinutes
        )
        NotificationCenter.default.post(name: .lockedAppsDidChange, object: nil)
        self.onConfigUpdated?()
    }

    // MARK: - Protection & Policy State Toggles
    func setProtectionDisabled(_ disabled: Bool) {
        self.isProtectionDisabled = disabled
        self.save()
        let status = disabled ? "disabled (protection paused)" : "enabled (protection active)"
        Logfile.policy.notice("[LockES] Application lock protection \(status, privacy: .public)")
        NotificationCenter.default.post(name: .protectionStatusDidChange, object: nil)
    }

    func setAllowIncomingCalls(_ allowed: Bool) {
        self.allowIncomingCalls = allowed
        self.save()
        let status = allowed ? "enabled (FaceTime/Phone bypass allowed)" : "disabled (FaceTime/Phone locked)"
        Logfile.policy.notice("[LockES] Allow incoming calls while locked: \(status, privacy: .public)")
    }

    func setAutoLockTimeoutMinutes(_ minutes: Int) {
        self.autoLockTimeoutMinutes = minutes
        self.save()
    }

    func isLocked(at path: String) -> Bool {
        if isProtectionDisabled { return false }
        return lockedApps[path] != nil
    }
}
