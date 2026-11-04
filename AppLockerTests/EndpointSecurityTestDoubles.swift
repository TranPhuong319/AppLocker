//
//  EndpointSecurityTestDoubles.swift
//  AppLockerTests
//
//  Created by Doe Phương on 4/11/26.
//

import Darwin
import EndpointSecurity
import Foundation
import os

struct RecordedBlockedExec: Sendable, Equatable {
    let name: String
    let path: String
    let cdhash: String
    let pid: Int32
}

final class MockAuthResponder: ESAuthResponding, @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock()
    private(set) var callCount: Int = 0
    private(set) var lastResult: es_auth_result_t?
    private(set) var lastCache: Bool?
    private(set) var lastMethod: ESResponseMethod?

    @discardableResult
    func respond(_ result: es_auth_result_t, cache: Bool) -> Bool {
        lock.withLock {
            callCount += 1
            lastResult = result
            lastCache = cache
            return true
        }
    }

    func recordMethod(_ method: ESResponseMethod, cache: Bool) -> es_respond_result_t {
        lock.withLock {
            callCount += 1
            lastCache = cache
            lastMethod = method
            switch method {
            case .authResult(let auth):
                lastResult = auth
            case .flagsResult(let flags):
                lastResult = (flags == 0xFFFFFFFF) ? ES_AUTH_RESULT_ALLOW : ES_AUTH_RESULT_DENY
            }
            return ES_RESPOND_RESULT_SUCCESS
        }
    }
}

final class MockESXPCNotificationSink: NSObject, ESXPCProtocol, @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock()
    private(set) var blockedExecEvents: [RecordedBlockedExec] = []
    private(set) var exitedPIDs: [Int32] = []

    func notifyBlockedExec(name: String, path: String, cdhash: String, pid: Int32) {
        lock.withLock {
            blockedExecEvents.append(RecordedBlockedExec(name: name, path: path, cdhash: cdhash, pid: pid))
        }
    }

    func notifyProcessExited(pid: Int32) {
        lock.withLock { exitedPIDs.append(pid) }
    }
}

final class MockXPCNotificationDelegate: NSObject, NSXPCListenerDelegate {
    let sink: MockESXPCNotificationSink
    init(sink: MockESXPCNotificationSink) { self.sink = sink }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection conn: NSXPCConnection) -> Bool {
        conn.exportedInterface = NSXPCInterface(with: ESXPCProtocol.self)
        conn.exportedObject = sink
        conn.resume()
        return true
    }
}
