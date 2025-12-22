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
    @Published var authError: String? = nil
    private var pendingAuthSHAs = Set<String>()
    
    func start() {
        Logfile.core.log("XPCServer start (app side exported object)")
        let arr = AppState.shared.manager.lockedApps.values.map { $0.toDict() }
        DispatchQueue.global().async {
            ESXPCClient.shared.updateBlockedApps(arr)
        }
    }
    
    // Extension -> App notification when exec attempted and extension denied
    func notifyBlockedExec(name: String, path: String, sha: String) {
        // 1. Kiểm tra nếu request này đã và đang hiển thị bảng Auth rồi
        if pendingAuthSHAs.contains(sha) {
            Logfile.core.info("Skipping duplicate auth request for: \(name) (SHA: \(sha.prefix(8)))")
            return
        }

        // 2. Đánh dấu SHA này là đang chờ xác thực
        pendingAuthSHAs.insert(sha)

        Logfile.core.log(
            """
            Endpoint Security Blocked Apps
            Name:   \(name, privacy: .public)
            Path:   \(path, privacy: .public)
            SHA256: \(sha.prefix(8), privacy: .public)
            Authorization...
            """
        )

        AuthenticationManager.authenticate(
            reason: "verify that you are opening the %@ app".localized(with: name)
        ) { [weak self] success, error in
            // Đảm bảo luôn dọn dẹp danh sách chờ khi kết thúc
            defer {
                DispatchQueue.main.async {
                    self?.pendingAuthSHAs.remove(sha)
                }
            }

            DispatchQueue.main.async {
                if success {
                    ESXPCClient.shared.allowSHAOnce(sha) { accepted in
                        DispatchQueue.main.async {
                            if accepted {
                                Logfile.core.info("ES accepted allowSHAOnce for \(sha.prefix(8), privacy: .public)")
                                
                                // Relaunch app
                                let appBundleURL = URL(fileURLWithPath: path)
                                    .deletingLastPathComponent()  // MacOS
                                    .deletingLastPathComponent()  // Contents
                                    .deletingLastPathComponent()  // App bundle root
                                NSWorkspace.shared.open(appBundleURL)
                            } else {
                                Logfile.core.error("ES rejected allowSHAOnce for \(sha.prefix(8))")
                                self?.authError = "ES extension did not approve"
                            }
                        }
                    }
                } else {
                    Logfile.core.error("Error authenticating user: \(error as NSObject?, privacy: .public)")
                    self?.authError = "Authentication failed"
                }
            }
        }
    }
}
