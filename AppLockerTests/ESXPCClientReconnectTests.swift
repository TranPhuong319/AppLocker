//
//  ESXPCClientReconnectTests.swift
//  AppLockerTests
//
//  Created by Doe Phương on 25/11/26.
//

import Darwin
import Foundation
import os
import Testing

@Suite("ESXPCClient Auto-Reconnect & Retry Lifecycle Tests", .serialized)
struct ESXPCClientReconnectTests {
    @Test("Transient server invalidation keeps extension installed flag and reconnects automatically")
    func transientInvalidationReconnectsAutomatically() async throws {
        let manager = ESManager(isTesting: true)
        manager.customConnectionValidator = { audit_token_to_pid($0.auditToken) == getpid() }

        let listener = NSXPCListener.anonymous()
        listener.delegate = manager
        listener.resume()
        defer { listener.invalidate() }
        let endpoint = listener.endpoint

        let connectCount = OSAllocatedUnfairLock(initialState: 0)
        let maxRetriesCount = OSAllocatedUnfairLock(initialState: 0)
        let isInstalled = OSAllocatedUnfairLock(initialState: true)

        let config = ESXPCClientConfiguration(
            maxRetries: 5,
            connectionFactory: { Self.makeUnresumedConnection(endpoint: endpoint) },
            isExtensionInstalled: { isInstalled.withLock { $0 } },
            onConnectionEstablished: { connectCount.withLock { $0 += 1 } },
            onMaxRetriesReached: { maxRetriesCount.withLock { $0 += 1 } },
            reconnectDelay: { _, _ in 0.02 }
        )

        let client = ESXPCClient(configuration: config, connectOnInit: false)
        defer { client.disconnect() }

        client.connect()
        try await waitUntil { connectCount.withLock { $0 } >= 1 }
        #expect(connectCount.withLock { $0 } == 1)

        // Simulate ESExtension process crash/restart by invalidating server-side XPC connection
        let serverConn = manager.xpcConnectionLock.withLock { manager.activeConnections.first }?.connection
        serverConn?.invalidate()

        try await waitUntil { connectCount.withLock { $0 } >= 2 }

        #expect(isInstalled.withLock { $0 } == true)
        #expect(connectCount.withLock { $0 } == 2)
        #expect(maxRetriesCount.withLock { $0 } == 0)
    }

    @Test("Exhausting maxRetries invokes onMaxRetriesReached exactly once and stops")
    func exhaustedRetriesTriggersCallbackOnce() async throws {
        let manager = ESManager(isTesting: true)
        manager.customConnectionValidator = { _ in false }

        let listener = NSXPCListener.anonymous()
        listener.delegate = manager
        listener.resume()
        defer { listener.invalidate() }
        let endpoint = listener.endpoint

        let maxRetriesCount = OSAllocatedUnfairLock(initialState: 0)
        let config = ESXPCClientConfiguration(
            maxRetries: 2,
            connectionFactory: { Self.makeUnresumedConnection(endpoint: endpoint) },
            isExtensionInstalled: { true },
            onConnectionEstablished: {},
            onMaxRetriesReached: { maxRetriesCount.withLock { $0 += 1 } },
            reconnectDelay: { _, _ in 0.01 }
        )

        let client = ESXPCClient(configuration: config, connectOnInit: false)
        defer { client.disconnect() }

        client.connect()
        try await waitUntil { maxRetriesCount.withLock { $0 } >= 1 }

        try await Task.sleep(for: .milliseconds(80))
        #expect(maxRetriesCount.withLock { $0 } == 1)
        #expect(client.shouldReconnect == false)
    }

    @Test("Explicit disconnect cancels pending reconnect attempts")
    func explicitDisconnectCancelsPendingReconnect() async throws {
        let manager = ESManager(isTesting: true)
        manager.customConnectionValidator = { _ in false }

        let listener = NSXPCListener.anonymous()
        listener.delegate = manager
        listener.resume()
        defer { listener.invalidate() }
        let endpoint = listener.endpoint

        let maxRetriesCount = OSAllocatedUnfairLock(initialState: 0)
        let config = ESXPCClientConfiguration(
            maxRetries: 3,
            connectionFactory: { Self.makeUnresumedConnection(endpoint: endpoint) },
            isExtensionInstalled: { true },
            onConnectionEstablished: {},
            onMaxRetriesReached: { maxRetriesCount.withLock { $0 += 1 } },
            reconnectDelay: { _, _ in 0.15 }
        )

        let client = ESXPCClient(configuration: config, connectOnInit: false)
        client.connect()
        try await Task.sleep(for: .milliseconds(40))
        client.disconnect()

        try await waitUntil { !client.shouldReconnect }
        try await Task.sleep(for: .milliseconds(200))
        #expect(maxRetriesCount.withLock { $0 } == 0)
        #expect(client.shouldReconnect == false)
    }

    @Test("Transport error does not double-count retries and uses backoff during handshake")
    func transportErrorCountsExactRetriesAndUsesBackoff() async throws {
        let listener = NSXPCListener.anonymous()
        let deadEndpoint = listener.endpoint
        listener.resume()
        listener.invalidate()

        let connectionAttempts = OSAllocatedUnfairLock(initialState: 0)
        let maxRetriesCount = OSAllocatedUnfairLock(initialState: 0)
        let recordedSchedule = OSAllocatedUnfairLock(initialState: [(attempt: Int, immediate: Bool)]())

        let config = ESXPCClientConfiguration(
            maxRetries: 4,
            connectionFactory: {
                connectionAttempts.withLock { $0 += 1 }
                return Self.makeUnresumedConnection(endpoint: deadEndpoint)
            },
            isExtensionInstalled: { true },
            onConnectionEstablished: {},
            onMaxRetriesReached: { maxRetriesCount.withLock { $0 += 1 } },
            reconnectDelay: { attempt, immediate in
                recordedSchedule.withLock { $0.append((attempt, immediate)) }
                return 0.01
            }
        )

        let client = ESXPCClient(configuration: config, connectOnInit: false)
        defer { client.disconnect() }

        client.connect()
        try await waitUntil { maxRetriesCount.withLock { $0 } >= 1 }
        try await Task.sleep(for: .milliseconds(80))

        #expect(connectionAttempts.withLock { $0 } == 5)
        #expect(maxRetriesCount.withLock { $0 } == 1)
        #expect(client.shouldReconnect == false)
        let schedule = recordedSchedule.withLock { $0 }
        #expect(schedule.map(\.attempt) == [1, 2, 3, 4])
        #expect(schedule.allSatisfy { !$0.immediate })
    }

    @Test("Explicit connect cancels pending delayed retry and resets retry state")
    func explicitConnectCancelsPendingRetryTimer() async throws {
        let deadListener = NSXPCListener.anonymous()
        let deadEndpoint = deadListener.endpoint
        deadListener.resume()
        deadListener.invalidate()

        let liveManager = ESManager(isTesting: true)
        liveManager.customConnectionValidator = { audit_token_to_pid($0.auditToken) == getpid() }
        let liveListener = NSXPCListener.anonymous()
        liveListener.delegate = liveManager
        liveListener.resume()
        defer { liveListener.invalidate() }
        let liveEndpoint = liveListener.endpoint

        let activeEndpoint = OSAllocatedUnfairLock(initialState: deadEndpoint)
        let connectCount = OSAllocatedUnfairLock(initialState: 0)
        let maxRetriesCount = OSAllocatedUnfairLock(initialState: 0)
        let scheduledDelaysCount = OSAllocatedUnfairLock(initialState: 0)

        let config = ESXPCClientConfiguration(
            maxRetries: 3,
            connectionFactory: {
                let endpoint = activeEndpoint.withLock { $0 }
                return Self.makeUnresumedConnection(endpoint: endpoint)
            },
            isExtensionInstalled: { true },
            onConnectionEstablished: { connectCount.withLock { $0 += 1 } },
            onMaxRetriesReached: { maxRetriesCount.withLock { $0 += 1 } },
            reconnectDelay: { _, _ in
                scheduledDelaysCount.withLock { $0 += 1 }
                return 0.25
            }
        )

        let client = ESXPCClient(configuration: config, connectOnInit: false)
        defer { client.disconnect() }

        client.connect()
        try await waitUntil { scheduledDelaysCount.withLock { $0 } >= 1 }

        activeEndpoint.withLock { $0 = liveEndpoint }
        client.connect()

        try await waitUntil { connectCount.withLock { $0 } >= 1 }
        try await Task.sleep(for: .milliseconds(300))

        #expect(connectCount.withLock { $0 } == 1)
        #expect(scheduledDelaysCount.withLock { $0 } == 1)
        #expect(maxRetriesCount.withLock { $0 } == 0)
        #expect(client.shouldReconnect == true)
    }

    private func waitUntil(
        timeout: Duration = .seconds(2),
        condition: @Sendable () -> Bool
    ) async throws {
        let deadline = ContinuousClock.now + timeout
        while !condition() && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    private static func makeUnresumedConnection(endpoint: NSXPCListenerEndpoint) -> NSXPCConnection {
        let conn = NSXPCConnection(listenerEndpoint: endpoint)
        conn.remoteObjectInterface = NSXPCInterface(with: ESAppProtocol.self)
        conn.exportedInterface = NSXPCInterface(with: ESXPCProtocol.self)
        conn.exportedObject = MockESXPCNotificationSink()
        return conn
    }
}
