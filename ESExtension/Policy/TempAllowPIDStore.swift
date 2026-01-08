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
        // Nếu không lấy được lock ngay lập tức, trả về false để tránh block
        return stateLock.trySync(default: false) {
            guard let expiry = allowedPIDs[pid] else { return false }
            if expiry > now { return true }
            allowedPIDs.removeValue(forKey: pid)
            return false
        }
    }
}
