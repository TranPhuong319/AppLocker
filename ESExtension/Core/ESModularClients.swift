//
//  ESModularClients.swift
//  ESExtension
//
//  Created by Doe Phương on 21/01/26.
//

import EndpointSecurity
import Foundation
import os

class ESClientObject {
    var client: OpaquePointer?
    let name: String
    let queue: DispatchQueue
    weak var manager: ESManager?

    init(name: String) {
        self.name = name
        // Santa Pattern: Use concurrent queues for high performance
        self.queue = DispatchQueue(
            label: "com.AppLocker.ES.\(name)", qos: .userInitiated, attributes: .concurrent)
    }

    deinit {
        if let clientPtr = client {
            es_delete_client(clientPtr)
        }
    }

    func createClient(
        handler: @escaping (OpaquePointer, ESMessage, ESSafetyValve) -> Void
    ) -> Bool {
        // 1. Create New Client
        let result = es_new_client(&client) { [weak self] (esClient, esMessage) in
            guard let self = self else {
                // If self is nil, just respond allow to not block invalid state
                if esMessage.pointee.action_type == ES_ACTION_TYPE_AUTH {
                    es_respond_auth_result(esClient, esMessage, ES_AUTH_RESULT_ALLOW, false)
                }
                return
            }
            
            // 2. Wrap Message & Valve
            let message = ESMessage(client: esClient, message: esMessage)
            
            // Non-AUTH messages don't need deadline logic
            if esMessage.pointee.action_type != ES_ACTION_TYPE_AUTH {
                if let manager = self.manager {
                     manager.authorizationProcessingQueue.async {
                         handler(esClient, message, ESSafetyValve(message: message, manager: manager))
                     }
                }
                return
            }

            // 3. AUTH Handling - Santa Semaphore Logic
            if let currentManager = self.manager {
                let valve = ESSafetyValve(message: message, manager: currentManager)
                
                // --- CALC BUDGET ---
                let deadline = message.pointee.deadline
                let now = mach_absolute_time()
                let timeUntilDeadline = (deadline > now) ? (deadline - now) : 0
                let nanosUntilDeadline = ESManager.machTimeToNanos(timeUntilDeadline)
                
                // Default Budget: 80% (Santa)
                let budget = Double(nanosUntilDeadline) * 0.8
                
                // Headroom: Time reserved for the deadline block to execute response
                let headroom = Int64(nanosUntilDeadline) - Int64(budget)
                
                // Clamp Headroom (Min 1s, Max 5s) - Santa Logic [1s, 5s]
                let minHeadroom: Int64 = 1_000_000_000  // 1 second
                let maxHeadroom: Int64 = 5_000_000_000  // 5 seconds
                let finalHeadroom = min(maxHeadroom, max(minHeadroom, headroom))
                
                let finalProcessingBudget = max(0, Int64(nanosUntilDeadline) - finalHeadroom)
                
                // --- SEMAPHORES ---
                let processingSema = DispatchSemaphore(value: 0)
                processingSema.signal() // Init value to 1 (Santa pattern)
                
                let deadlineExpiredSema = DispatchSemaphore(value: 0)
                
                // --- DEADLINE TASK (Fail-Closed Deny) ---
                currentManager.emergencyTimerQueue.asyncAfter(
                    deadline: .now() + .nanoseconds(Int(finalProcessingBudget))) {
                        
                    // Try to acquire token. If success (0), it means Processing hasn't finished.
                    if processingSema.wait(timeout: .now()) == .success {
                        // Timeout Reached! Fail Closed.
                        // Exception: Allow if it is AppLocker itself (already muted/handled? No, mute removes AUTH events generally)
                        // But if for some reason we get an event, DENY to be safe.
                        
                        _ = valve.respond(ES_AUTH_RESULT_DENY, cache: false)
                        
                        let path = ESSafetyValve.getPath(message)
                        Logfile.es.error("DEADLINE REACHED [DENY]: \(path) (Budget: \(finalProcessingBudget)ns)")
                        
                        // Signal that we are done responding
                        deadlineExpiredSema.signal()
                    }
                }
                
                // --- PROCESSING TASK ---
                currentManager.authorizationProcessingQueue.async {
                    // Do the work (calls valve.respond internally)
                    handler(esClient, message, valve)
                    
                    // Try to acquire token.
                    if processingSema.wait(timeout: .now()) == .success {
                        // We finished in time! Code flow normal.
                    } else {
                        // Deadline task stole the token. We were too slow.
                        // Wait for deadline task to finish its log/signal to ensure clean exit.
                        deadlineExpiredSema.wait()
                    }
                }
                
            } else {
                // No Manager (Deallocated?) - Fail Safe
                es_respond_auth_result(esClient, esMessage, ES_AUTH_RESULT_ALLOW, false)
            }
        }

        if result != ES_NEW_CLIENT_RESULT_SUCCESS {
            Logfile.es.pLog("[\(self.name)] Failed to create client: \(result.rawValue)")
            return false
        }
        
        Logfile.es.pLog("[\(self.name)] Client created at Addr: \(String(format: "%p", Int(bitPattern: self.client!)))")
        
        // 4. Early Mute (Self Protection)
        // Must mute immediately to prevent self-lockout/generation storms
        self.muteSelf()
        
        return true
    }

    @discardableResult
    func muteSelf() -> Bool {
        guard let client = client else { return false }

        var token = audit_token_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<audit_token_t>.size / MemoryLayout<integer_t>.size)

        let res = withUnsafeMutablePointer(to: &token) { tPtr in
            tPtr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { iPtr in
                return withUnsafeMutablePointer(to: &count) { cPtr in
                    return task_info(mach_task_self_, task_flavor_t(TASK_AUDIT_TOKEN), iPtr, cPtr)
                }
            }
        }

        if res == KERN_SUCCESS {
            let muteRes = es_mute_process(client, &token)
            if muteRes == ES_RETURN_SUCCESS {
                Logfile.es.pLog("[\(self.name)] Mute self result: Success")
                return true
            } else {
                Logfile.es.pError("[\(self.name)] Mute self result: \(muteRes.rawValue)")
                return false
            }
        } else {
            Logfile.es.pError("[\(self.name)] Failed to get self audit token: \(res)")
            return false
        }
    }

    func subscribe(_ events: [es_event_type_t]) -> Bool {
        guard let client = client else { return false }
        let result = es_subscribe(client, events, UInt32(events.count))
        Logfile.es.pLog("[\(self.name)] Subscribe result: \(result.rawValue)")
        return result == ES_RETURN_SUCCESS
    }
}

class ESAuthorizer: ESClientObject {
    init() {
        super.init(name: "Authorizer")
    }

    func start() -> Bool {
        return self.createClient { [weak self] (esClient, esMessage, valve) in
            self?.handleAuthExec(client: esClient, message: esMessage, valve: valve)
        }
    }

    func enable() {
        // MuteSelf moved to createClient, but calling it again here is harmless and safe checks
        _ = self.muteSelf()
        _ = self.subscribe([ES_EVENT_TYPE_AUTH_EXEC])
    }

    private func handleAuthExec(client: OpaquePointer, message: ESMessage, valve: ESSafetyValve)
    {
        ESManager.handleAuthExec(client: client, message: message, valve: valve)
    }
}

class ESTamper: ESClientObject {
    init() {
        super.init(name: "TamperResistance")
    }

    func start() -> Bool {
        return self.createClient { [weak self] (esClient, esMessage, valve) in
            self?.handleFileEvent(client: esClient, message: esMessage, valve: valve)
        }
    }

    func enable() {
        self.muteSelf()

        // Santa Pattern: Inverted Muting for target paths
        Logfile.es.log("[\(self.name)] Enabling Inverted Muting (Santa-Style)...")

        _ = es_unmute_all_target_paths(self.client!)

        let invRes = es_invert_muting(self.client!, ES_MUTE_INVERSION_TYPE_TARGET_PATH)
        Logfile.es.pLog("[\(self.name)] Invert muting result: \(invRes.rawValue)")

        self.setupWhitelist()

        _ = self.subscribe([
            ES_EVENT_TYPE_AUTH_OPEN,
            ES_EVENT_TYPE_AUTH_UNLINK,
            ES_EVENT_TYPE_AUTH_RENAME,
            ES_EVENT_TYPE_AUTH_TRUNCATE,
            ES_EVENT_TYPE_AUTH_EXCHANGEDATA,
            ES_EVENT_TYPE_AUTH_CLONE,
            ES_EVENT_TYPE_AUTH_LINK,
        ])
    }

    private func setupWhitelist() {
        // Santa Pattern: Mute target paths using TARGET_LITERAL
        // In Inverted Mode, 'Mute' actually means 'Watch'
        let paths: [(path: String, type: es_mute_path_type_t)] = [
            ("/Users/Shared/AppLocker/config.plist", ES_MUTE_PATH_TYPE_TARGET_LITERAL),
            ("/Users/Shared/AppLocker", ES_MUTE_PATH_TYPE_TARGET_PREFIX),
        ]

        for item in paths {
            let res = es_mute_path(self.client!, item.path, item.type)
            Logfile.es.pLog("[\(self.name)] Whitelist [\(item.path)] result: \(res.rawValue)")
        }
    }

    private func handleFileEvent(
        client: OpaquePointer,
        message: ESMessage,
        valve: ESSafetyValve
    ) {
        let type = message.pointee.event_type
        let path = ESSafetyValve.getPath(message)

        // Log protected path access
        Logfile.es.pLog("FILE_EVENT_PROTECTED [\(type.rawValue)] Path:[\(path)]")

        switch type {
        case ES_EVENT_TYPE_AUTH_OPEN:
            ESManager.handleAuthOpen(
                client: client,
                message: message,
                valve: valve
            )
        case ES_EVENT_TYPE_AUTH_UNLINK:
            ESManager.handleAuthUnlink(
                client: client,
                message: message,
                valve: valve
            )
        case ES_EVENT_TYPE_AUTH_RENAME:
            ESManager.handleAuthRename(
                client: client,
                message: message,
                valve: valve
            )
        case ES_EVENT_TYPE_AUTH_TRUNCATE:
            ESManager.handleAuthTruncate(
                client: client,
                message: message,
                valve: valve
            )
        case ES_EVENT_TYPE_AUTH_EXCHANGEDATA:
            ESManager.handleAuthExchangedata(
                client: client,
                message: message,
                valve: valve
            )
        case ES_EVENT_TYPE_AUTH_CLONE:
            ESManager.handleAuthClone(
                client: client,
                message: message,
                valve: valve
            )
        case ES_EVENT_TYPE_AUTH_LINK:
            ESManager.handleAuthLink(
                client: client,
                message: message,
                valve: valve
            )
        default:
            if message.pointee.action_type == ES_ACTION_TYPE_AUTH {
                _ = valve.respond(ES_AUTH_RESULT_ALLOW, cache: true)
            }
        }
    }
}
