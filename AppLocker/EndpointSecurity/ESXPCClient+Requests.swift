//
//  ESXPCClient+Requests.swift
//  AppLocker
//
//  Created by Doe Phương on 4/10/26.
//

import Foundation

// MARK: - XPC Request Actions
extension ESXPCClient {
    func updateLanguage(_ langCode: String) {
        xpcQueue.async { [weak self] in
            guard let self = self, let conn = self.connection else {
                Logfile.appXPC.debug("[ESXPCClient] Connection not ready, skipping language update")
                return
            }

            guard let proxy = self.proxy(conn: conn, actionName: "updateLanguage") else { return }
            proxy.updateLanguage(to: langCode)
            Logfile.appXPC.debug("[ESXPCClient] updateLanguage sent: \(langCode, privacy: .public)")
        }
    }

    // App requests extension to allow config access once (with reply ack)
    func allowConfigAccess(_ processID: Int32, retry: Int = 0, completion: @escaping @Sendable (Bool) -> Void) {
        xpcQueue.async { [weak self] in
            guard let self else {
                completion(false)
                return
            }

            guard retry <= 10 else {
                Logfile.appXPC.error("[ESXPCClient] allowConfigAccess: Max retries reached, giving up.")
                completion(false)
                return
            }

            guard let conn = self.connection else {
                self.xpcQueue.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                    self?.allowConfigAccess(processID, retry: retry + 1, completion: completion)
                }
                return
            }

            guard let proxy = self.proxy(conn: conn, actionName: "allowConfigAccess", onError: { completion(false) })
            else { return }

            proxy.allowConfigAccess(processID) { success in
                let replyStatus = success ? "success" : "fail"
                Logfile.appXPC.debug(
                    """
                    [ESXPCClient] allowConfigAccess reply: \(replyStatus, privacy: .public) \
                    for PID=\(processID, privacy: .public)
                    """
                )
                completion(success)
            }
        }
    }

    func authorizeShutdown(_ authorized: Bool, completion: @escaping @Sendable (Bool) -> Void) {
        xpcQueue.async { [weak self] in
            guard let self = self, let conn = self.connection else {
                completion(false)
                return
            }

            guard let proxy = self.proxy(conn: conn, actionName: "authorizeShutdown", onError: { completion(false) })
            else { return }

            proxy.authorizeShutdown(authorized) { success in
                Logfile.appXPC.debug("[ESXPCClient] authorizeShutdown reply: \(success, privacy: .public)")
                completion(success)
            }
        }
    }

    func processPendingApps(
        approvedPIDs: [Int32],
        rejectedPIDs: [Int32],
        retry: Int = 0,
        completion: @escaping @Sendable (Bool) -> Void
    ) {
        xpcQueue.async { [weak self] in
            guard let self else {
                completion(false)
                return
            }

            guard retry <= 5 else {
                Logfile.appXPC.error("[ESXPCClient] processPendingApps retry limit reached (connection unavailable)")
                completion(false)
                return
            }

            guard let conn = self.connection else {
                self.xpcQueue.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                    self?.processPendingApps(
                        approvedPIDs: approvedPIDs,
                        rejectedPIDs: rejectedPIDs,
                        retry: retry + 1,
                        completion: completion
                    )
                }
                return
            }

            guard let proxy = self.proxy(conn: conn, actionName: "processPendingApps", onError: { completion(false) })
            else { return }

            proxy.processPendingApps(approvedPIDs: approvedPIDs, rejectedPIDs: rejectedPIDs) { success in
                Logfile.appXPC.debug(
                    """
                    [ESXPCClient] processPendingApps reply: \(success, privacy: .public) \
                    (Approved: \(approvedPIDs, privacy: .public), Rejected: \(rejectedPIDs, privacy: .public))
                    """
                )
                completion(success)
            }
        }
    }

    func updateIncomingCallRingingState(_ isRinging: Bool) {
        xpcQueue.async { [weak self] in
            guard let self, let conn = self.connection else {
                Logfile.appXPC.debug("[ESXPCClient] Connection not ready, skipping call state update")
                return
            }

            guard let proxy = self.proxy(conn: conn, actionName: "updateIncomingCallRingingState") else { return }
            proxy.updateIncomingCallRingingState(isRinging)
            Logfile.appXPC.debug("[ESXPCClient] updateIncomingCallRingingState sent: \(isRinging, privacy: .public)")
        }
    }
}
