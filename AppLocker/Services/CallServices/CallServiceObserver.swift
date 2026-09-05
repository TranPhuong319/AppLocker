//
//  CallServiceObserver.swift
//  AppLocker
//
//  Created by Doe Phương on 5/9/26.
//

import Foundation
import os

@MainActor
final class CallServiceObserver {
    static let shared = CallServiceObserver()

    private var notifyToken: Int32 = -1
    private var isCurrentlyRinging = false

    private init() {}

    func startMonitoring() {
        guard notifyToken == -1 else { return }

        Logfile.policy.info("[CallObserver] Starting Call Services monitoring via activity notifications...")

        var token: Int32 = 0
        let status = notify_register_dispatch(
            "com.apple.sharing.activity-level-changed",
            &token,
            DispatchQueue.main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleNotificationFired()
            }
        }

        guard status == NOTIFY_STATUS_OK else {
            Logfile.policy.error(
                "[CallObserver] Failed to register activity notification dispatch: \(status, privacy: .public)"
            )
            return
        }

        notifyToken = token
        handleNotificationFired()
    }

    func stopMonitoring() {
        guard notifyToken != -1 else { return }

        notify_cancel(notifyToken)
        notifyToken = -1

        if isCurrentlyRinging {
            isCurrentlyRinging = false
            ESXPCClient.shared.updateIncomingCallRingingState(false)
        }
        Logfile.policy.info("[CallObserver] Stopped Call Services monitoring.")
    }

    private func handleNotificationFired() {
        guard notifyToken != -1 else { return }

        var state: UInt64 = 0
        guard notify_get_state(notifyToken, &state) == NOTIFY_STATUS_OK else { return }

        // State 14 corresponds to PhoneCall activity level in sharingd
        let isCallActive = (state == 14)
        updateRingingState(isCallActive)
    }

    private func updateRingingState(_ isRinging: Bool) {
        guard isCurrentlyRinging != isRinging else { return }
        isCurrentlyRinging = isRinging

        if isRinging {
            Logfile.policy.notice("[CallObserver] Active incoming call detected. Updating ES extension.")
        } else {
            Logfile.policy.debug("[CallObserver] Incoming call cleared. Updating ES extension.")
        }

        ESXPCClient.shared.updateIncomingCallRingingState(isRinging)
    }
}
