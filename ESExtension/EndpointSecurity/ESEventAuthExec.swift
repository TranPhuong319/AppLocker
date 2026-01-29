//
//  ESEventAuthExec.swift
//  ESExtension
//
//  Created by Doe Phương on 2/1/26.
//

import EndpointSecurity
import Foundation
import Darwin
import os

extension ESManager {
    static func handleAuthExec(
        client: OpaquePointer,
        message: ESMessage,
        valve: ESSafetyValve
    ) {
        let arrivalTime = Date()
        let messagePtr = message.pointee
        
        guard let path = safePath(fromFilePointer: messagePtr.event.exec.target.pointee.executable) else {
            Logfile.es.log("Missing exec path in AUTH_EXEC. Denying by default.")
            _ = valve.respond(ES_AUTH_RESULT_DENY, cache: false)
            return
        }

        guard let manager = ESManager.sharedInstanceForCallbacks else {
            Logfile.es.log("No ESManager instance. Denying exec.")
            _ = valve.respond(ES_AUTH_RESULT_DENY, cache: false)
            return
        }

        let parentPid = messagePtr.process.pointee.ppid
        var signingID = "Unsigned/Unknown"
        if let signingToken = messagePtr.event.exec.target.pointee.signing_id.data {
            signingID = String(cString: signingToken)
        }

        func sendNotifications(sha: String, decision: ExecDecision) {
            if decision == .deny {
                DispatchQueue.global(qos: .userInteractive).async {
                    TTYNotifier.notify(
                        parentPid: parentPid, blockedPath: path, sha: sha, identifier: signingID)
                }
                DispatchQueue.global(qos: .utility).async {
                    let name = manager.computeAppName(forExecPath: path)
                    manager.sendBlockedNotificationToApp(name: name, path: path, sha: sha)
                }
            }
        }

        // Fast path — single lock read of all state.
        let decisionResult: ExecDecision? = manager.stateLock.sync {
            if let mappedSHA = manager.blockedPathToSHA[path] {
                if let expiry = manager.tempAllowedSHAs[mappedSHA], expiry > Date() {
                    return .allow
                }
                if manager.blockedSHAs.contains(mappedSHA) {
                    return .deny
                }
            }
            if let cached = manager.decisionCache[path] {
                return cached
            }
            return nil
        }

        if let decision = decisionResult {
            let authResult = (decision == .allow) ? ES_AUTH_RESULT_ALLOW : ES_AUTH_RESULT_DENY
            
            // Dynamic Delay Calculation (Budget-Aware)
            // Goal: Add ~200ms delay for Deny to prevent Finder error, but respect Deadline.
            if decision == .deny {
                let deadline = messagePtr.deadline
                let now = mach_absolute_time()
                
                if deadline > now {
                    var info = mach_timebase_info()
                    mach_timebase_info(&info)
                    
                    let remainingTicks = deadline - now
                    let remainingNanos = remainingTicks * UInt64(info.numer) / UInt64(info.denom)
                    let remainingSeconds = TimeInterval(remainingNanos) / 1_000_000_000
                    
                    // Configuration
                    let targetDelay: TimeInterval = 0.2 // 200ms optimal for Finder
                    let safetyBuffer: TimeInterval = 1.0 // Reserve 1s for overhead/safety
                    
                    // Logic: Take targetDelay ONLY if we have (target + buffer) time left.
                    // Otherwise, take whatever is left minus buffer.
                    // If remaining < buffer, do not sleep at all.
                    let availableSleep = max(0, remainingSeconds - safetyBuffer)
                    let actualDelay = min(targetDelay, availableSleep)
                    
                    if actualDelay > 0.01 { // Only sleep if meaningful
                        Thread.sleep(forTimeInterval: actualDelay)
                    }
                }
            }
            
            // Use valve to safely respond
            _ = valve.respond(authResult, cache: false)  // NEVER cache to ensure locks work immediately

            if decision == .deny {
                Logfile.es.pLog("Denied by FastPath (Cache/Map): \(path)")
                let shaForNotify = manager.stateLock.sync {
                    manager.blockedPathToSHA[path] ?? "Cached-No-SHA"
                }
                sendNotifications(sha: shaForNotify, decision: .deny)
            }
            return
        }

        // Slow path — compute SHA outside the lock.
        // Limit concurrency to avoid CPU thrashing
        // CONSISTENCY CHECK:
        // We must calculate SHA exactly like the Main App (using SHA_READ_LIMIT).
        // Check if we have enough budget to perform the STANDARD hash.
        // We do NOT adjust the size dynamically anymore, as that breaks consistency.
        
        let deadline = messagePtr.deadline
        let now = mach_absolute_time()
        var shouldHash = true
        
        if deadline > now {
            var info = mach_timebase_info()
            mach_timebase_info(&info)
            let remainingTicks = deadline - now
            let remainingNanos = remainingTicks * UInt64(info.numer) / UInt64(info.denom)
            let remainingSeconds = TimeInterval(remainingNanos) / 1_000_000_000
            
            // Standard Requirement: 5MB at 50MB/s = 0.1s processing time.
            // Safety Buffer: 1.0s.
            // Required Time = 1.1s.
            let requiredTime = 1.1 
            
            if remainingSeconds < requiredTime {
                shouldHash = false
                Logfile.es.log("Skipping SHA calc: Not enough budget for consistent hash (Has: \(String(format: "%.2f", remainingSeconds))s, Need: \(requiredTime)s)")
            }
        }
        
        var sha: String? = nil
        if shouldHash {
            manager.shaSemaphore.wait()
            sha = computeSHA(forPath: path) // Uses default SHA_READ_LIMIT (5MB)
            manager.shaSemaphore.signal()
        }

        if let sha = sha {
            let finalDecision: ExecDecision = manager.stateLock.sync {
                if let expiry = manager.tempAllowedSHAs[sha], expiry > Date() {
                    return .allow
                }
                return manager.blockedSHAs.contains(sha) ? .deny : .allow
            }

            manager.stateLock.perform {
                manager.blockedPathToSHA[path] = sha
                manager.decisionCache[path] = finalDecision
            }

            let authResult = (finalDecision == .allow) ? ES_AUTH_RESULT_ALLOW : ES_AUTH_RESULT_DENY
            
            // Dynamic Delay for Slow Path (Small files might be hashed too fast)
            if finalDecision == .deny {
                let deadline = messagePtr.deadline
                let now = mach_absolute_time()
                
                if deadline > now {
                    var info = mach_timebase_info()
                    mach_timebase_info(&info)
                    
                    let remainingTicks = deadline - now
                    let remainingNanos = remainingTicks * UInt64(info.numer) / UInt64(info.denom)
                    let remainingSeconds = TimeInterval(remainingNanos) / 1_000_000_000
                    
                    let targetDelay: TimeInterval = 0.2
                    let safetyBuffer: TimeInterval = 1.0
                    
                    let availableSleep = max(0, remainingSeconds - safetyBuffer)
                    let actualDelay = min(targetDelay, availableSleep)
                    
                    if actualDelay > 0.01 {
                        Thread.sleep(forTimeInterval: actualDelay)
                    }
                }
            }

            // Use valve to safely respond
            let elapsed = Date().timeIntervalSince(arrivalTime)
            if valve.respond(authResult, cache: false) { // NEVER cache ALLOW to ensure locks work immediately
                // Only log and notify if WE responded (not the timer)
                if finalDecision == .deny {
                    Logfile.es.pLog("Denied by SlowPath (SHA) in \(String(format: "%.2fs", elapsed)): \(path)")
                    sendNotifications(sha: sha, decision: .deny)
                } else {
                    // Logfile.es.pLog("Allowed by SlowPath (SHA) in \(String(format: "%.2fs", elapsed)): \(path)")
                }
            } else {
                Logfile.es.log("Late response for SHA in \(String(format: "%.2fs", elapsed)): \(path) (Timer won)")
            }
            return

        } else {
            _ = valve.respond(ES_AUTH_RESULT_DENY, cache: false)
            Logfile.es.pLog("Failed to compute SHA -> Denying: \(path)")
            sendNotifications(sha: "Read-Error", decision: .deny)
            return
        }
    }
}
