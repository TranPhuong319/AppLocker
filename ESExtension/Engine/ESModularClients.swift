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

    func createClient() -> Bool {
        // 1. Create New Client
        let result = es_new_client(&(self.client)) { [weak self] (esClient, esMessage) in
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
                         // Use the internal handler for non-auth messages too
                         let handler = self.makeAuthHandler(for: message)
                         handler(esClient, message, ESSafetyValve(message: message, manager: manager))
                     }
                }
                return
            }

            // 3. AUTH Handling - Santa Semaphore Logic
            // CRITICAL FIX: Only AUTH events need deadline logic. NOTIFY events (like EXIT) must skip this.
            if esMessage.pointee.action_type == ES_ACTION_TYPE_AUTH {
                if let currentManager = self.manager {
                    let handler = self.makeAuthHandler(for: message)
                    self.handleMessageWithDeadline(
                        esClient: esClient,
                        message: message,
                        manager: currentManager,
                        handler: handler
                    )
                } else {
                    // No Manager (Deallocated?) - Fail Safe
                    es_respond_auth_result(esClient, esMessage, ES_AUTH_RESULT_ALLOW, false)
                }
            } else {
                // NOTIFY EVents (like EXIT)
                if let manager = self.manager {
                     manager.authorizationProcessingQueue.async {
                         ESManager.handleNotifyExit(client: esClient, message: message)
                     }
                }
            }
        }

        if result != ES_NEW_CLIENT_RESULT_SUCCESS {
            Logfile.endpointSecurity.log("[\(self.name)] Failed to create client: \(result.rawValue)")
            return false
        }

        if let client = self.client {
            Logfile.endpointSecurity.log(
                "[\(self.name)] Client created at Addr: \(String(format: "%p", Int(bitPattern: client)))"
            )
        }

        // 4. Early Mute (Self Protection)
        // Must mute immediately to prevent self-lockout/generation storms
        self.muteSelf()

        return true
    }

    private func makeAuthHandler(for message: ESMessage) -> (OpaquePointer, ESMessage, ESSafetyValve) -> Void {
        let eventType = message.pointee.event_type
        return { (client, msg, valve) in
            switch eventType {
            case ES_EVENT_TYPE_AUTH_EXEC:
                ESManager.handleAuthExec(client: client, message: msg, valve: valve)
            case ES_EVENT_TYPE_AUTH_OPEN:
                ESManager.handleAuthOpen(client: client, message: msg, valve: valve)
            case ES_EVENT_TYPE_AUTH_UNLINK:
                ESManager.handleAuthUnlink(client: client, message: msg, valve: valve)
            case ES_EVENT_TYPE_AUTH_RENAME:
                ESManager.handleAuthRename(client: client, message: msg, valve: valve)
            case ES_EVENT_TYPE_AUTH_TRUNCATE:
                ESManager.handleAuthTruncate(client: client, message: msg, valve: valve)
            case ES_EVENT_TYPE_AUTH_EXCHANGEDATA:
                ESManager.handleAuthExchangedata(client: client, message: msg, valve: valve)
            case ES_EVENT_TYPE_AUTH_CLONE:
                ESManager.handleAuthClone(client: client, message: msg, valve: valve)
            case ES_EVENT_TYPE_AUTH_LINK:
                ESManager.handleAuthLink(client: client, message: msg, valve: valve)
            case ES_EVENT_TYPE_NOTIFY_EXIT:
                ESManager.handleNotifyExit(client: client, message: msg)
            default:
                if msg.pointee.action_type == ES_ACTION_TYPE_AUTH {
                    _ = valve.respond(ES_AUTH_RESULT_ALLOW, cache: true)
                }
            }
        }
    }

    private func handleMessageWithDeadline(
        esClient: OpaquePointer,
        message: ESMessage,
        manager: ESManager,
        handler: @escaping (OpaquePointer, ESMessage, ESSafetyValve) -> Void
    ) {
        let valve = ESSafetyValve(message: message, manager: manager)

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

        // --- DEADLINE TASK (Fail-Closed Deny) ---
        manager.emergencyTimerQueue.asyncAfter(
            deadline: .now() + .nanoseconds(Int(finalProcessingBudget))) {

            // Try to acquire token. If success (0), it means Processing hasn't finished.
            if processingSema.wait(timeout: .now()) == .success {
                // Timeout Reached! Fail Closed.
                _ = valve.respond(ES_AUTH_RESULT_DENY, cache: false)

                let path = ESSafetyValve.getPath(message)
                Logfile.endpointSecurity.error("DEADLINE REACHED [DENY]: \(path) (Budget: \(finalProcessingBudget)ns)")
                
                // Signal that we are done responding
                // The valve itself handles the signal internally when respond() is called.
            }
        }

        // --- PROCESSING TASK ---
        manager.authorizationProcessingQueue.async {
            // Do the work (calls valve.respond internally)
            handler(esClient, message, valve)

            // Try to acquire token.
            if processingSema.wait(timeout: .now()) == .success {
                // We finished in time! Code flow normal.
            } else {
                // Deadline task stole the token. We were too slow.
                // Wait for deadline task to finish its log/signal to ensure clean exit.
                valve.wait()
            }
        }
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
                Logfile.endpointSecurity.log("[\(self.name)] Mute self result: Success")
                return true
            } else {
                Logfile.endpointSecurity.error("[\(self.name)] Mute self result: \(muteRes.rawValue)")
                return false
            }
        } else {
            Logfile.endpointSecurity.error("[\(self.name)] Failed to get self audit token: \(res)")
            return false
        }
    }

    func subscribe(_ events: [es_event_type_t]) -> Bool {
        guard let client = client else { return false }
        let result = es_subscribe(client, events, UInt32(events.count))
        Logfile.endpointSecurity.log("[\(self.name)] Subscribe result: \(result.rawValue)")
        return result == ES_RETURN_SUCCESS
    }
}

class ESAuthorizer: ESClientObject {
    init() {
        super.init(name: "Authorizer")
    }

    func start() -> Bool {
        return self.createClient()
    }

    func enable() {
        // MuteSelf moved to createClient, but calling it again here is harmless and safe checks
        _ = self.muteSelf()
        _ = self.subscribe([
            ES_EVENT_TYPE_AUTH_EXEC,
            ES_EVENT_TYPE_NOTIFY_EXIT
        ])
    }
}

class ESTamper: ESClientObject {
    init() {
        super.init(name: "TamperResistance")
    }

    func start() -> Bool {
        return self.createClient()
    }

    func enable() {
        #if DEBUG
        Logfile.endpointSecurity.log("Skip enable ESTamper (Debug mode)")
        #else
        self.muteSelf()

        // Santa Pattern: Inverted Muting for target paths
        Logfile.endpointSecurity.log("[\(self.name)] Enabling Inverted Muting (Santa-Style)...")

        if let client = self.client {
            _ = es_unmute_all_target_paths(client)

            let invRes = es_invert_muting(client, ES_MUTE_INVERSION_TYPE_TARGET_PATH)
            Logfile.endpointSecurity.log("[\(self.name)] Invert muting result: \(invRes.rawValue)")
        }

        self.setupAllowlist()

        _ = self.subscribe([
            ES_EVENT_TYPE_AUTH_OPEN,
            ES_EVENT_TYPE_AUTH_UNLINK,
            ES_EVENT_TYPE_AUTH_RENAME,
            ES_EVENT_TYPE_AUTH_TRUNCATE,
            ES_EVENT_TYPE_AUTH_EXCHANGEDATA,
            ES_EVENT_TYPE_AUTH_CLONE,
            ES_EVENT_TYPE_AUTH_LINK
        ])
        #endif
    }

    private func setupAllowlist() {
        // Santa Pattern: Mute target paths using TARGET_LITERAL
        // In Inverted Mode, 'Mute' actually means 'Watch'
        let paths: [(path: String, type: es_mute_path_type_t)] = [
            ("/Users/Shared/AppLocker/config.plist", ES_MUTE_PATH_TYPE_TARGET_LITERAL),
            ("/Users/Shared/AppLocker", ES_MUTE_PATH_TYPE_TARGET_PREFIX),
            ("/Applications/AppLocker.app", ES_MUTE_PATH_TYPE_TARGET_PREFIX)
        ]

        if let client = self.client {
            for item in paths {
                let res = es_mute_path(client, item.path, item.type)
                Logfile.endpointSecurity.log("[\(self.name)] Allowlist [\(item.path)] result: \(res.rawValue)")
            }
        }
    }
}
