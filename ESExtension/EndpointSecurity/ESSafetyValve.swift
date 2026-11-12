//
//  ESSafetyValve.swift
//  ESExtension
//
//  Created by Doe Phương on 31/7/26.
//

import EndpointSecurity
import Foundation
import os

enum ESResponseMethod: Sendable, Equatable {
    case authResult(es_auth_result_t)
    case flagsResult(UInt32)
}

protocol ESAuthResponding: Sendable {
    @discardableResult
    func respond(_ result: es_auth_result_t, cache: Bool) -> Bool
}

/// ESSafetyValve implements the "Dual-Block Race" pattern (Santa-style).
/// It uses a lock to ensure that either the main logic worker
/// OR the emergency timer responds to the ES message, but never both.
final class ESSafetyValve: ESAuthResponding, @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock()
    private let message: ESMessage?
    private let eventType: es_event_type_t
    private let actionType: es_action_type_t
    private let customResponder: (@Sendable (ESResponseMethod, Bool) -> es_respond_result_t)?
    private var isResponded = false

    init(message: ESMessage, manager: ESManager) {
        self.message = message
        self.eventType = message.pointee.event_type
        self.actionType = message.pointee.action_type
        self.customResponder = nil
    }

    init(
        eventType: es_event_type_t,
        actionType: es_action_type_t = ES_ACTION_TYPE_AUTH,
        responder: @escaping @Sendable (ESResponseMethod, Bool) -> es_respond_result_t = { _, _ in
            ES_RESPOND_RESULT_SUCCESS
        }
    ) {
        self.message = nil
        self.eventType = eventType
        self.actionType = actionType
        self.customResponder = responder
    }

    /// Thread-safe response method.
    /// - Returns: `true` if this call was the one that actually responded.
    @discardableResult
    func respond(_ result: es_auth_result_t, cache: Bool) -> Bool {
        let shouldRespond = lock.withLock { () -> Bool in
            guard !isResponded else { return false }
            isResponded = true
            return true
        }
        guard shouldRespond else { return false }

        let method: ESResponseMethod = (eventType == ES_EVENT_TYPE_AUTH_OPEN)
            ? .flagsResult(result == ES_AUTH_RESULT_ALLOW ? 0xFFFFFFFF : 0)
            : .authResult(result)

        let status = dispatchResponse(method: method, cache: cache)
        if status != ES_RESPOND_RESULT_SUCCESS, let message = self.message {
            let path = ESSafetyValve.path(for: message)
            Logfile.endpointSecurity.error(
                """
                [SafetyValve] es_respond failed [\(status.rawValue, privacy: .public)] \
                for \(path, privacy: .public) (Type: \(self.eventType.rawValue, privacy: .public))
                """
            )
        }
        return true
    }

    private func dispatchResponse(method: ESResponseMethod, cache: Bool) -> es_respond_result_t {
        if let customResponder {
            return customResponder(method, cache)
        }
        guard let message else { return ES_RESPOND_RESULT_SUCCESS }
        switch method {
        case .flagsResult(let allowedFlags):
            return es_respond_flags_result(message.client, message.rawMessage, allowedFlags, cache)
        case .authResult(let authResult):
            return es_respond_auth_result(message.client, message.rawMessage, authResult, cache)
        }
    }

    /// Helper to extract path for logging.
    static func path(for message: ESMessage) -> String {
        let type = message.pointee.event_type
        let messagePtr = message.pointee
        switch type {
        case ES_EVENT_TYPE_AUTH_EXEC:
            return safePath(fromFilePointer: messagePtr.event.exec.target.pointee.executable) ?? "unknown_exec"
        case ES_EVENT_TYPE_AUTH_OPEN:
            return safePath(fromFilePointer: messagePtr.event.open.file) ?? "unknown_open"
        case ES_EVENT_TYPE_AUTH_UNLINK:
            return safePath(fromFilePointer: messagePtr.event.unlink.target) ?? "unknown_unlink"
        case ES_EVENT_TYPE_AUTH_RENAME:
            return safePath(fromFilePointer: messagePtr.event.rename.source) ?? "unknown_rename"
        case ES_EVENT_TYPE_AUTH_TRUNCATE:
            return safePath(fromFilePointer: messagePtr.event.truncate.target) ?? "unknown_truncate"
        default: return "Event-\(type.rawValue)"
        }
    }

    deinit {
        // Fallback: If for some reason respond was NEVER called, do it now.
        // BUT only for AUTH events. NOTIFY events do not need response.
        if !isResponded && actionType == ES_ACTION_TYPE_AUTH {
            _ = respond(ES_AUTH_RESULT_ALLOW, cache: false)
        }
    }
}
