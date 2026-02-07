//
//  ESEventNotifyExit.swift
//  ESExtension
//
//  Created by Doe Phương on 07/02/26.
//

import EndpointSecurity
import Foundation
import os

extension ESManager {
    static func handleNotifyExit(client: OpaquePointer, message: ESMessage) {
        guard let manager = sharedInstanceForCallbacks else { return }
        
        // 1. Check if it's our main app
        let process = message.pointee.process
        guard manager.isMainAppProcess(process) else {
            return
        }
        
        let pid = audit_token_to_pid(process.pointee.audit_token)
        Logfile.endpointSecurity.log("Guardian: Main App (pid: \(pid)) exited.")
        
        // 2. Check if shutdown was authorized
        let isAuthorized = manager.stateLock.sync { manager.isShutdownAuthorized }
        
        if isAuthorized {
            Logfile.endpointSecurity.log("Guardian: Shutdown was authorized. Watchdog standing down.")
            return
        }
        
        // 3. Unauthorized exit detected -> Self-Healing with 10s delay
        Logfile.endpointSecurity.warning("Guardian: Unauthorized exit detected! Launching watchdog (10s delay)...")
        
        let uid = manager.stateLock.sync { manager.activeUserUID }
        guard let userUID = uid else {
            Logfile.endpointSecurity.error("Guardian: No active User UID found. Cannot kickstart.")
            return
        }
        
        // Schedule kickstart after 10 seconds
        manager.authorizationProcessingQueue.asyncAfter(deadline: .now() + 10.0) {
            Logfile.endpointSecurity.log("Guardian: Watchdog checking if Main App has recovered...")
            
            // Check if app is already running (launchd might have restarted it via KeepAlive)
            if manager.authenticatedMainAppPID != nil {
                Logfile.endpointSecurity.log("Guardian: Main App recovered via launchd. Watchdog cancelled.")
            } else {
                Logfile.endpointSecurity.warning("Guardian: Main App still down. Forcing recovery for UID: \(userUID)")
                AppLauncherUtils.forceEnableAndRestartAgent(for: userUID)
            }
        }
    }
}
