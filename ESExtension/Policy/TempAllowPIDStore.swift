//
//  TempAllowPIDStore.swift
//  ESExtension
//
//  Created by Doe Phương on 2/1/26.
//

import Foundation

extension ESManager {
    func isPIDAllowed(_ pid: pid_t) -> Bool {
        let now = Date()
        // Use regular sync - stateLock is fast enough for this critical path
        return stateLock.sync {
            guard let expiry = _allowedPIDs[pid] else { return false }
            if expiry > now { return true }
            _allowedPIDs.removeValue(forKey: pid)
            return false
        }
    }
}
