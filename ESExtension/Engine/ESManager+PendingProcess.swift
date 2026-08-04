//
//  ESManager+PendingProcess.swift
//  ESExtension
//
//  Created by Doe Phương on 31/7/26.
//

import Darwin
import Foundation
import os

extension ESManager {
    // MARK: - Pending Verification PID & Path Management

    func markPendingVerification(pid: pid_t) {
        pendingPIDLock.perform {
            _ = pendingVerificationPIDs.insert(pid)
        }
    }

    private func normalizePath(_ path: String) -> String {
        return (path as NSString).standardizingPath
    }

    func markPendingVerificationPath(path: String, cdhash: String, parentPid: pid_t, uid: uid_t, signingID: String) {
        let key = normalizePath(path)
        let info = PendingExecInfo(
            cdhash: cdhash,
            parentPid: parentPid,
            uid: uid,
            signingID: signingID,
            timestamp: Date()
        )
        let now = Date()
        stateLock.perform {
            // Clean up stale pending paths older than 60s to prevent memory leaks
            self.pendingVerificationPaths = self.pendingVerificationPaths.compactMapValues { queue in
                let valid = queue.filter { now.timeIntervalSince($0.timestamp) < 60 }
                return valid.isEmpty ? nil : valid
            }
            self.pendingVerificationPaths[key, default: []].append(info)
        }
        Logfile.endpointSecurity.log("Marked path \(key) as pending verification")
    }

    func peekPendingVerificationInfo(forPath path: String) -> PendingExecInfo? {
        let key = normalizePath(path)
        let realKey = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        return stateLock.sync {
            // 1. Direct match
            if let queue = pendingVerificationPaths[key], let first = queue.first {
                return first
            }
            if let queue = pendingVerificationPaths[realKey], let first = queue.first {
                return first
            }
            if key != path, let queue = pendingVerificationPaths[path], let first = queue.first {
                return first
            }
            // 2. Bundle path match (if path is inside an .app bundle)
            var url = URL(fileURLWithPath: path)
            while url.pathComponents.count > 1 {
                if url.pathExtension.lowercased() == "app" {
                    if let bundle = Bundle(url: url), let mainExec = bundle.executablePath {
                        let normPath = normalizePath(path)
                        let normMainExec = normalizePath(mainExec)
                        guard normPath == normMainExec else { return nil }
                    }
                    let appPath = normalizePath(url.path)
                    let realAppPath = url.resolvingSymlinksInPath().path
                    if let queue = pendingVerificationPaths[appPath], let first = queue.first {
                        return first
                    }
                    if let queue = pendingVerificationPaths[realAppPath], let first = queue.first {
                        return first
                    }
                    for (pendingKey, queue) in pendingVerificationPaths {
                        if (pendingKey.hasPrefix(appPath) || pendingKey.hasPrefix(realAppPath)) && !queue.isEmpty {
                            return queue.first
                        }
                    }
                    break
                }
                url.deleteLastPathComponent()
            }
            return nil
        }
    }

    func isPendingVerification(pid: pid_t) -> Bool {
        return pendingPIDLock.sync {
            pendingVerificationPIDs.contains(pid)
        }
    }

    func removePendingVerification(pid: pid_t) {
        pendingPIDLock.perform {
            pendingVerificationPIDs.remove(pid)
        }
    }

    // MARK: - Batch Execution (SIGCONT / SIGKILL)

    func processPendingBatch(approved: [Int32], rejected: [Int32]) -> Bool {
        var processedCount = 0

        // Process Approved PIDs (SIGCONT)
        for rawPID in approved {
            let pid = pid_t(rawPID)
            // ponytail: Safety guard: never pass pid <= 0 to kill() to prevent process group signals
            guard pid > 0 else { continue }

            let wasPending = pendingPIDLock.sync {
                pendingVerificationPIDs.remove(pid) != nil
            }

            if wasPending {
                // Send SIGCONT to resume the suspended application
                let res = kill(pid, SIGCONT)
                if res == 0 {
                    Logfile.endpointSecurity.log("Successfully sent SIGCONT to approved PID \(pid)")
                } else {
                    Logfile.endpointSecurity.error("Failed to send SIGCONT to PID \(pid): errno \(errno)")
                }
                processedCount += 1
            }
        }

        // Process Rejected PIDs (SIGKILL)
        for rawPID in rejected {
            let pid = pid_t(rawPID)
            // ponytail: Safety guard: never pass pid <= 0 to kill() to prevent process group signals
            guard pid > 0 else { continue }

            let wasPending = pendingPIDLock.sync {
                pendingVerificationPIDs.remove(pid) != nil
            }

            if wasPending {
                // Send SIGKILL to terminate the suspended application
                let res = kill(pid, SIGKILL)
                if res == 0 {
                    Logfile.endpointSecurity.log("Successfully sent SIGKILL to rejected PID \(pid)")
                } else {
                    Logfile.endpointSecurity.error("Failed to send SIGKILL to PID \(pid): errno \(errno)")
                }
                processedCount += 1
            }
        }

        return processedCount > 0 || (approved.isEmpty && rejected.isEmpty)
    }
}
