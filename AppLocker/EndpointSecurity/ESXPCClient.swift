//
//  ESXPCClient.swift
//  AppLocker
//
//  Created by Doe Phương on 27/9/25.
//


import Foundation
import os

final class ESXPCClient {
    static let shared = ESXPCClient()
    private var connection: NSXPCConnection?
    private let serviceName = "endpoint-security.com.TranPhuong319.AppLocker.ESExtension.xpc"
    private let maxRetries = 10
    private var retryCount = 0

    // pending queue if updateBlockedApps called before connection ready
    private var lastKnownBlockedApps: [[String: String]] = []

    private init() {
        // tiny delay to avoid race but keep it short
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.connect()
        }
    }

    private let xpcQueue = DispatchQueue(
        label: "endpoint-security.com.TranPhuong319.AppLocker.ESExtension.xpc.qos",
        qos: .userInitiated
    )

    func connect() {
        Logfile.core.log("[ESXPCClient] Connecting to MachService: \(self.serviceName, privacy: .public)")

        let conn = NSXPCConnection(machServiceName: serviceName)
        conn.remoteObjectInterface = NSXPCInterface(with: ESAppProtocol.self)

        conn.exportedInterface = NSXPCInterface(with: ESXPCProtocol.self)
        conn.exportedObject = XPCServer.shared

        conn.invalidationHandler = { [weak self] in
            Logfile.core.error("[ESXPCClient] Connection invalidated")
            self?.scheduleReconnect(immediate: true)
        }

        conn.interruptionHandler = { [weak self] in
            Logfile.core.error("[ESXPCClient] Connection interrupted")
            self?.scheduleReconnect(immediate: false)
        }

        conn.resume()

        self.connection = conn
        self.retryCount = 0
        Logfile.core.log("[ESXPCClient] Connected & ready")

        // Flush pending apps trên queue ưu tiên cao
        if !lastKnownBlockedApps.isEmpty {
            let copy = lastKnownBlockedApps
            xpcQueue.async { [weak self] in
                self?.updateBlockedApps(copy)
            }
        }
    }

    private func scheduleReconnect(immediate: Bool) {
        connection?.invalidate()
        connection = nil

        guard retryCount < maxRetries else {
            Logfile.core.error("[ESXPCClient] Max retries reached (\(self.maxRetries))")
            return
        }
        retryCount += 1

        let delay: Double
        if immediate {
            delay = 0.05 // try quickly
        } else {
            delay = min(0.5 * Double(retryCount), 1.0) // gentle backoff but small cap
        }

        Logfile.core.log("[ESXPCClient] Retrying in \(delay, format: .fixed(precision: 2))s (attempt \(self.retryCount))")
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.connect()
        }
    }

    // Public API
    // Accepts Swift array of dicts, converts to NSArray for XPC
    func updateBlockedApps(_ apps: [[String: String]]) {
        guard let conn = connection else {
            Logfile.core.log("[ESXPCClient] Connection not ready, queueing updateBlockedApps")
            lastKnownBlockedApps = apps
            return
        }

        guard let proxy = conn.remoteObjectProxyWithErrorHandler({ error in
            Logfile.core.error("updateBlockedApps failed: \(String(describing: error), privacy: .public)")
        }) as? ESAppProtocol else {
            Logfile.core.error("[ESXPCClient] No valid proxy to send update")
            return
        }

        let ns = apps.map { NSDictionary(dictionary: $0) } as NSArray
        proxy.updateBlockedApps(ns)
        Logfile.core.log("updateBlockedApps sent (\(apps.count, privacy: .public) items)")
    }

    // App requests extension to allow SHA once (with reply ack)
    func allowSHAOnce(_ sha: String, completion: @escaping (Bool) -> Void) {
        guard let conn = connection else {
            // quick retry once after 50ms
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.05) {
                self.allowSHAOnce(sha, completion: completion)
            }
            return
        }

        guard let proxy = conn.remoteObjectProxyWithErrorHandler({ error in
            Logfile.core.error("allowSHAOnce failed: \(String(describing: error), privacy: .public)")
            completion(false)
        }) as? ESAppProtocol else {
            Logfile.core.error("[ESXPCClient] No valid proxy to send allowSHAOnce")
            completion(false)
            return
        }

        proxy.allowSHAOnce(sha) { success in
            Logfile.core.log("allowSHAOnce reply: \(success ? "success" : "fail") for SHA=\(sha, privacy: .public)")
            completion(success)
        }
    }
    // App requests extension to allow config access once (with reply ack)
    func allowConfigAccess(_ pid: Int32, completion: @escaping (Bool) -> Void) {
        guard let conn = connection else {
            // quick retry once after 50ms
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.05) {
                self.allowConfigAccess(pid, completion: completion)
            }
            return
        }

        guard let proxy = conn.remoteObjectProxyWithErrorHandler({ error in
            Logfile.core.error("allowConfigAccess failed: \(String(describing: error), privacy: .public)")
            completion(false)
        }) as? ESAppProtocol else {
            Logfile.core.error("[ESXPCClient] No valid proxy to send allowConfigAccess")
            completion(false)
            return
        }

        proxy.allowConfigAccess(pid) { success in
            Logfile.core.log("allowConfigAccess reply: \(success ? "success" : "fail") for PID=\(pid)")
            completion(success)
        }
    }

}
