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
        stateLock.perform { [weak self] in
            guard let self = self else { return }
            let now = Date()
            let countBefore = self.tempAllowedSHAs.count
            self.tempAllowedSHAs = self.tempAllowedSHAs.filter { $0.value > now }
            let removedCount = countBefore - self.tempAllowedSHAs.count
            if removedCount > 0 {
                Logfile.es.log("Temp allowed SHAs expired: \(removedCount, privacy: .public)")
            }
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
            Logfile.es.log("Temp allowed SHA: \(sha, privacy: .public) until \(expiry, privacy: .public)")
        }
    }

    @objc func allowSHAOnce(_ sha: String, withReply reply: @escaping (Bool) -> Void) {
        allowTempSHA(sha)
        reply(true)
    }
}
