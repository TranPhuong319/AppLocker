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
    private let logger = Logger(subsystem: "com.TranPhuong319.AppLocker", category: "XPCServer")

    @Published var authError: String? = nil
    
    func start() {
        Logfile.core.log("XPCServer start (app side exported object)")
        let arr = AppState.shared.manager.lockedApps.values.map { $0.toDict() }
        DispatchQueue.global().async {
            ESXPCClient.shared.updateBlockedApps(arr)
        }
    }
    
    // Extension -> App notification when exec attempted and extension denied
    func notifyBlockedExec(name: String, path: String, sha: String) {
        Logfile.core.log("notifyBlockedExec name=\(name, privacy: .public) path=\(path, privacy: .public) sha=\(sha, privacy: .public). Authorization…")
        
        AuthenticationManager.authenticate(
            reason: "verify that you are opening the %@ app".localized(with: name)
        ) { success, error in
            DispatchQueue.main.async {
                if success {
                    ESXPCClient.shared.allowSHAOnce(sha) { accepted in
                        DispatchQueue.main.async {
                            if accepted {
                                self.logger.log("✅ ES accepted allowSHAOnce for \(sha.prefix(8), privacy: .public)")
                                // Relaunch app bundle sau khi ES confirm
                                let appBundleURL = URL(fileURLWithPath: path)
                                    .deletingLastPathComponent()  // MacOS
                                    .deletingLastPathComponent()  // Contents
                                    .deletingLastPathComponent()  // App bundle root
                                NSWorkspace.shared.open(appBundleURL)
                            } else {
                                self.logger.error("❌ ES rejected allowSHAOnce for \(sha.prefix(8), privacy: .public)")
                                self.authError = "ES extension did not approve"
                            }
                        }
                    }
                } else {
                    Logfile.core.error("Error authenticating user: \(error as NSObject?, privacy: .public)")
                    self.authError = "Authentication failed"
                }
            }
        }
    }
}
