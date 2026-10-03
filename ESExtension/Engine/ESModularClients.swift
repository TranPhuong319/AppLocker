//
//  ESModularClients.swift
//  ESExtension
//
//  Created by Doe Phương on 21/01/26.
//

import EndpointSecurity
import Foundation
import os

class ESClientObject: @unchecked Sendable {
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
            guard let self else {
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
                guard let manager = self.manager else { return }
                let handler = self.makeAuthHandler(for: message)
                let valve = ESSafetyValve(message: message, manager: manager)
                if esMessage.pointee.event_type == ES_EVENT_TYPE_NOTIFY_EXEC {
                    handler(message.client, message, valve)
                } else {
                    manager.authorizationProcessingQueue.async {
                        handler(message.client, message, valve)
                    }
                }
                return
            }

            // AUTH Handling — Santa Semaphore Logic
            if let currentManager = self.manager {
                let handler = self.makeAuthHandler(for: message)
                self.handleMessageWithDeadline(
                    esClient: esClient,
                    message: message,
                    manager: currentManager,
                    handler: handler
                )
            } else {
                es_respond_auth_result(esClient, esMessage, ES_AUTH_RESULT_ALLOW, false)
            }
        }

        if result != ES_NEW_CLIENT_RESULT_SUCCESS {
            let resCode = result.rawValue
            Logfile.endpointSecurity.error(
                "[ESClient] [\(self.name, privacy: .public)] Failed to create client: \(resCode, privacy: .public)"
            )
            return false
        }

        if let client = self.client {
            let addrStr = String(format: "%p", Int(bitPattern: client))
            Logfile.endpointSecurity.debug(
                "[ESClient] [\(self.name, privacy: .public)] Client created at Addr: \(addrStr, privacy: .public)"
            )
        }

        self.muteSelf()
        return true
    }

    private func makeAuthHandler(
        for message: ESMessage
    ) -> @Sendable (OpaquePointer, ESMessage, ESSafetyValve) -> Void {
        let eventType = message.pointee.event_type
        return { (client, msg, valve) in
            if !self.dispatchProcessEvent(eventType, client: client, msg: msg, valve: valve) {
                self.dispatchFileAuthEvent(eventType, client: client, msg: msg, valve: valve)
            }
        }
    }

    private func dispatchProcessEvent(
        _ eventType: es_event_type_t,
        client: OpaquePointer,
        msg: ESMessage,
        valve: ESSafetyValve
    ) -> Bool {
        guard let manager = self.manager else { return false }
        switch eventType {
        case ES_EVENT_TYPE_AUTH_SIGNAL:
            manager.handleAuthSignal(client: client, message: msg, valve: valve)
        case ES_EVENT_TYPE_NOTIFY_EXEC:
            manager.handleNotifyExec(client: client, message: msg)
        case ES_EVENT_TYPE_NOTIFY_EXIT:
            manager.handleNotifyExit(client: client, message: msg)
        default:
            return false
        }
        return true
    }

    private func dispatchFileAuthEvent(
        _ eventType: es_event_type_t,
        client: OpaquePointer,
        msg: ESMessage,
        valve: ESSafetyValve
    ) {
        guard let manager = self.manager else {
            if msg.pointee.action_type == ES_ACTION_TYPE_AUTH {
                _ = valve.respond(ES_AUTH_RESULT_ALLOW, cache: true)
            }
            return
        }
        if !dispatchFileMutationEvent(eventType, manager: manager, client: client, msg: msg, valve: valve) {
            if msg.pointee.action_type == ES_ACTION_TYPE_AUTH {
                _ = valve.respond(ES_AUTH_RESULT_ALLOW, cache: true)
            }
        }
    }

    private func dispatchFileMutationEvent(
        _ eventType: es_event_type_t,
        manager: ESManager,
        client: OpaquePointer,
        msg: ESMessage,
        valve: ESSafetyValve
    ) -> Bool {
        switch eventType {
        case ES_EVENT_TYPE_AUTH_OPEN:
            manager.handleAuthOpen(client: client, message: msg, valve: valve)
        case ES_EVENT_TYPE_AUTH_UNLINK:
            manager.handleAuthUnlink(client: client, message: msg, valve: valve)
        case ES_EVENT_TYPE_AUTH_RENAME:
            manager.handleAuthRename(client: client, message: msg, valve: valve)
        case ES_EVENT_TYPE_AUTH_TRUNCATE:
            manager.handleAuthTruncate(client: client, message: msg, valve: valve)
        case ES_EVENT_TYPE_AUTH_EXCHANGEDATA:
            manager.handleAuthExchangedata(client: client, message: msg, valve: valve)
        case ES_EVENT_TYPE_AUTH_CLONE:
            manager.handleAuthClone(client: client, message: msg, valve: valve)
        case ES_EVENT_TYPE_AUTH_LINK:
            manager.handleAuthLink(client: client, message: msg, valve: valve)
        default:
            return false
        }
        return true
    }

    private func handleMessageWithDeadline(
        esClient: OpaquePointer,
        message: ESMessage,
        manager: ESManager,
        handler: @escaping @Sendable (OpaquePointer, ESMessage, ESSafetyValve) -> Void
    ) {
        let valve = ESSafetyValve(message: message, manager: manager)
        let deadline = message.pointee.deadline
        let now = mach_absolute_time()
        let timeRemaining = (deadline > now) ? (deadline - now) : 0
        let nanosUntilDeadline = ESManager.machTimeToNanos(timeRemaining)
        let budget = Double(nanosUntilDeadline) * 0.8
        let rawHeadroom = Int64(nanosUntilDeadline) - Int64(budget)
        let finalHeadroom = min(5_000_000_000, max(1_000_000_000, rawHeadroom))
        let finalProcessingBudget = max(0, Int64(nanosUntilDeadline) - finalHeadroom)

        manager.emergencyTimerQueue.asyncAfter(
            deadline: .now() + .nanoseconds(Int(finalProcessingBudget))) {
            if valve.respond(ES_AUTH_RESULT_DENY, cache: false) {
                let path = ESSafetyValve.getPath(message)
                Logfile.endpointSecurity.error(
                    """
                    [ESClient] DEADLINE REACHED [DENY]: \(path, privacy: .public) \
                    (Budget: \(finalProcessingBudget, privacy: .public)ns)
                    """
                )
            }
        }

        manager.authorizationProcessingQueue.async {
            handler(message.client, message, valve)
        }
    }

    @discardableResult
    func muteSelf() -> Bool {
        guard let client = client, var token = ESManager.selfAuditToken() else { return false }

        let muteRes = es_mute_process(client, &token)
        if muteRes == ES_RETURN_SUCCESS {
            Logfile.endpointSecurity.debug("[ESClient] [\(self.name, privacy: .public)] Mute self result: Success")
            return true
        } else {
            Logfile.endpointSecurity.error(
                "[ESClient] [\(self.name, privacy: .public)] Mute self result: \(muteRes.rawValue, privacy: .public)"
            )
            return false
        }
    }

    func subscribe(_ events: [es_event_type_t]) -> Bool {
        guard let client = client else { return false }
        let result = es_subscribe(client, events, UInt32(events.count))
        Logfile.endpointSecurity.debug(
            "[ESClient] [\(self.name, privacy: .public)] Subscribe result: \(result.rawValue, privacy: .public)"
        )
        return result == ES_RETURN_SUCCESS
    }
}

final class ESAuthorizer: ESClientObject, @unchecked Sendable {
    init() { super.init(name: "Authorizer") }
    func start() -> Bool { createClient() }

    func enable() {
        _ = self.subscribe([
            ES_EVENT_TYPE_NOTIFY_EXEC,
            ES_EVENT_TYPE_AUTH_SIGNAL,
            ES_EVENT_TYPE_NOTIFY_EXIT
        ])
    }
}

final class ESTamper: ESClientObject, @unchecked Sendable {
    init() { super.init(name: "TamperResistance") }
    func start() -> Bool { createClient() }

    func enable() {
        #if DEBUG
        Logfile.endpointSecurity.debug("[ESClient] Skip enable ESTamper (Debug mode)")
        #else
        self.muteSelf()
        Logfile.endpointSecurity.debug(
            "[ESClient] [\(self.name, privacy: .public)] Enabling Inverted Muting (Santa-Style)..."
        )
        if let client = self.client {
            _ = es_unmute_all_target_paths(client)
            let invRes = es_invert_muting(client, ES_MUTE_INVERSION_TYPE_TARGET_PATH)
            Logfile.endpointSecurity.debug(
                "[ESClient] [\(self.name, privacy: .public)] Invert muting result: \(invRes.rawValue, privacy: .public)"
            )
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
        let paths: [(path: String, type: es_mute_path_type_t)] = [
            ("/Users/Shared/AppLocker", ES_MUTE_PATH_TYPE_TARGET_PREFIX),
            ("/Applications/AppLocker.app", ES_MUTE_PATH_TYPE_TARGET_PREFIX)
        ]
        if let client = self.client {
            for item in paths {
                let res = es_mute_path(client, item.path, item.type)
                Logfile.endpointSecurity.debug(
                    """
                    [ESClient] [\(self.name, privacy: .public)] Allowlist [\(item.path, privacy: .public)] \
                    result: \(res.rawValue, privacy: .public)
                    """
                )
            }
        }
    }
}
