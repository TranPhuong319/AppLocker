//
//  XPCServer.swift
//  AppLocker
//
//  Created by Doe Phương on 27/9/25.
//

import Foundation
import os
import Combine
import AppKit

final class XPCServer: NSObject, ESXPCProtocol, ObservableObject {
    static let shared = XPCServer()
    @Published var authError: String?
    private var pendingAuthSHAs = Set<String>()
    private let authQueue = DispatchQueue(label: "com.TranPhuong319.AppLocker.auth.sha.queue")
    
    func start() {
        Logfile.core.log("XPCServer start (app side exported object)")
        let arr = AppState.shared.manager.lockedApps.values.map { $0.toDict() }
        DispatchQueue.global().async {
            ESXPCClient.shared.updateBlockedApps(arr)
        }
    }

    // Extension -> App notification when exec attempted and extension denied
    func notifyBlockedExec(name: String, path: String, sha: String) {

        // atomic check + insert
        let shouldProceed: Bool = authQueue.sync {
            if pendingAuthSHAs.contains(sha) {
                return false
            }
            pendingAuthSHAs.insert(sha)
            return true
        }

        if !shouldProceed {
            Logfile.core.info("Skipping duplicate auth request for SHA: \(sha.prefix(8))")
            return
        }

        Logfile.core.log(
            """
            Endpoint Security Blocked Apps
            Name:   \(name, privacy: .public)
            Path:   \(path, privacy: .public)
            SHA256: \(sha.prefix(8), privacy: .public)
            """
        )

        AuthenticationManager.authenticate(
            reason: "verify that you are opening the %@ app".localized(with: name)
        ) { [weak self] success, error in

            defer {
                self?.authQueue.async {
                    self?.pendingAuthSHAs.remove(sha)
                }
            }

            DispatchQueue.main.async {
                if success {
                    ESXPCClient.shared.allowSHAOnce(sha) { accepted in
                        if accepted {
                            let appBundleURL = URL(fileURLWithPath: path)
                                .deletingLastPathComponent()
                                .deletingLastPathComponent()
                                .deletingLastPathComponent()
                            NSWorkspace.shared.open(appBundleURL)
                        } else {
                            self?.authError = "ES extension did not approve"
                        }
                    }
                } else {
                    self?.authError = "Authentication failed"
                }
            }
        }
    }
}
