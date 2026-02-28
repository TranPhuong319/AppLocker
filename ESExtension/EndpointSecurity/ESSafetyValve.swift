import EndpointSecurity
import Foundation
import os

/// ESSafetyValve implements the "Dual-Block Race" pattern (Santa-style).
/// It uses a DispatchSemaphore to ensure that either the main logic worker
/// OR the emergency timer responds to the ES message, but never both.
final class ESSafetyValve {
    private let lock = FastLock()
    private let deadlineExpiredSema = DispatchSemaphore(value: 0)
    private let message: ESMessage
    private let manager: ESManager
    private var isResponded = false

    init(message: ESMessage, manager: ESManager) {
        self.message = message
        self.manager = manager

        // Track the count of active messages in the system
        OSAtomicIncrement32(&manager.activeMessageCount)
    }

    /// Thread-safe response method.
    /// - Returns: `true` if this call was the one that actually responded.
    @discardableResult
    func respond(_ result: es_auth_result_t, cache: Bool) -> Bool {
        var shouldRespond = false

        lock.perform {
            if !isResponded {
                isResponded = true
                shouldRespond = true
            }
        }

        if shouldRespond {
            let status: es_respond_result_t

            // CRITICAL FIX: AUTH_OPEN requires es_respond_flags_result
            if message.pointee.event_type == ES_EVENT_TYPE_AUTH_OPEN {
                let allowedFlags: UInt32 = (result == ES_AUTH_RESULT_ALLOW)
                ? 0xFFFFFFFF : 0
                status = es_respond_flags_result(
                    message.client,
                    message.rawMessage,
                    allowedFlags,
                    cache
                )
            } else {
                status = es_respond_auth_result(
                    message.client,
                    message.rawMessage,
                    result,
                    cache
                )
            }

            if status != ES_RESPOND_RESULT_SUCCESS {
                let path = ESSafetyValve.getPath(self.message)
                // swiftlint:disable:next line_length
                Logfile.endpointSecurity.error(
                """
                es_respond failed [\(status.rawValue, privacy: .public)] \
                for \(path, privacy: .public) \
                (Type: \(self.message.pointee.event_type.rawValue, privacy: .public))
                """
                )
            } else {
                // Log success mostly for debug (optional, can be noisy)
                // Logfile.endpointSecurity.debug("es_respond success for Type: \(self.message.pointee.event_type.rawValue)")
            }

            // Decrement active message counter
            OSAtomicDecrement32(&manager.activeMessageCount)

            // Signal that we are done to any waiting threads (usually the worker cleanup)
            deadlineExpiredSema.signal()
            return true
        }
        return false
    }

    /// Called when the deadline timer expires (Panic Mode).
    func fireEmergencyResponse() {
        // Santa-style: We usually fail-open (ALLOW) in emergency to prevent system freeze.
        if respond(ES_AUTH_RESULT_ALLOW, cache: true) {
             let path = ESSafetyValve.getPath(message)
             Logfile.endpointSecurity.error("SAFETY VALVE: Deadline reached for [\(path)]! Forced ALLOW to prevent SIGKILL.")
        }
    }

    /// Helper to extract path for logging.
    static func getPath(_ message: ESMessage) -> String {
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

    /// Wait until a response has been sent (to ensure object stays alive until timer finishes).
    func waitForResponse() {
        deadlineExpiredSema.wait()
        deadlineExpiredSema.signal()
    }
    
    /// Expose semaphore for external waiters (like ESModularClients)
    func wait() {
        deadlineExpiredSema.wait()
        deadlineExpiredSema.signal()
    }

    deinit {
        // Fallback: If for some reason respond was NEVER called, do it now.
        // BUT only for AUTH events. NOTIFY events do not need response.
        if !isResponded && message.pointee.action_type == ES_ACTION_TYPE_AUTH {
            _ = respond(ES_AUTH_RESULT_ALLOW, cache: false)
        }
    }
}
