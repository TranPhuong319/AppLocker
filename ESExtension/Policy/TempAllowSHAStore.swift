//
//  TempAllowStore.swift
//  ESExtension
//
//  Created by Doe Phương on 29/12/25.
//

import Foundation
import os

extension ESManager {
    func scheduleTempCleanup() {
        DispatchQueue.global().asyncAfter(deadline: .now() + 10) { [weak self] in
            self?.cleanupTempAllowed()
            self?.scheduleTempCleanup()
        }
    }

    // Fast in-place filter of expired entries under lock.
    func cleanupTempAllowed() {
        var removedCount = 0
        stateLock.perform { [weak self] in
            guard let self = self else { return }
            let now = Date()
            let countBefore = self.tempAllowedSHAs.count
            self.tempAllowedSHAs = self.tempAllowedSHAs.filter { $0.value > now }
            removedCount = countBefore - self.tempAllowedSHAs.count
        }

        if removedCount > 0 {
            Logfile.es.pLog("Temp allowed SHAs expired: \(removedCount)")
        }
    }

    // Check if a SHA is currently allowed by a temporary window.
    func isTempAllowed(_ sha: String) -> Bool {
        return stateLock.sync {
            if let expiry = tempAllowedSHAs[sha] {
                return expiry > Date()
            }
            return false
        }
    }

    func allowTempSHA(_ sha: String) {
        let expiry = Date().addingTimeInterval(self.allowWindowSeconds)

        stateLock.perform { [weak self] in
            guard let self = self else { return }
            self.tempAllowedSHAs[sha] = expiry
        }
        Logfile.es.pLog(
            "Temp allowed SHA: \(sha) until \(expiry)")
    }

    @objc func allowSHAOnce(_ sha: String, withReply reply: @escaping (Bool) -> Void) {
        guard isCurrentConnectionAuthenticated() else {
            Logfile.es.error("Unauthorized call to allowSHAOnce")
            reply(false)
            return
        }
        allowTempSHA(sha)
        reply(true)
    }
}
