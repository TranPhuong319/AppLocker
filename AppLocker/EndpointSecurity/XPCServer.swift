//
//  XPCServer.swift
//  AppLocker
//
//  Created by Doe Phương on 27/9/25.
//

import AppKit
import Combine
import Foundation
import os

final class XPCServer: NSObject, ESXPCProtocol, ObservableObject {
    static let shared = XPCServer()
    @Published var authError: String?
    private var pendingAuthSHAs = Set<String>()
    private let authQueue = DispatchQueue(label: "com.TranPhuong319.AppLocker.auth.sha.queue")
    private var authRequestQueue: [(name: String, path: String, sha: String)] = []
    private var isAuthenticating = false

    // Extension -> App notification when exec attempted and extension denied
    func notifyBlockedExec(name: String, path: String, sha: String) {
        // atomic check + insert vào pendingAuthSHAs để tránh trùng lặp cùng một app
        let shouldQueue: Bool = authQueue.sync {
            if pendingAuthSHAs.contains(sha) {
                return false
            }
            pendingAuthSHAs.insert(sha)
            authRequestQueue.append((name, path, sha))
            return true
        }

        if !shouldQueue {
            Logfile.core.info("Skipping duplicate auth request for SHA: \(sha.prefix(8))")
            return
        }

        Logfile.core.log(
            """
            Endpoint Security Blocked App added to Queue
            Name:   \(name)
            Path:   \(path)
            SHA256: \(sha.prefix(8))
            """
        )

        processNextAuthRequest()
    }

    private func processNextAuthRequest() {
        authQueue.async { [weak self] in
            guard let self = self, !self.isAuthenticating, !self.authRequestQueue.isEmpty else { return }
            
            self.isAuthenticating = true
            let request = self.authRequestQueue.removeFirst()
            
            Logfile.core.log("Processing Auth Request for: \(request.name)")
            
            // Đảm bảo App hiện lên trước khi hiện hộp thoại xác thực
            DispatchQueue.main.async {
                Logfile.core.log("Activating AppLocker for Auth Request...")
                NSApp.activate(ignoringOtherApps: true)
            }
            
            AuthenticationManager.authenticate(
                reason: String(localized: "verify that you are opening the \(request.name) app")
            ) { [weak self] success, error in
                guard let self = self else { return }
                
                if let error = error {
                    Logfile.core.error("Authentication error: \(error.localizedDescription)")
                }

                // Sau khi xác thực xong (bất kể thành công hay thất bại), dọn dẹp và xử lý request tiếp theo
                defer {
                    self.authQueue.async {
                        self.pendingAuthSHAs.remove(request.sha)
                        self.isAuthenticating = false
                        self.processNextAuthRequest()
                    }
                }

                if success {
                    DispatchQueue.main.async {
                        ESXPCClient.shared.allowSHAOnce(request.sha) { accepted in
                            if accepted {
                                let appBundleURL = URL(fileURLWithPath: request.path)
                                    .deletingLastPathComponent()
                                    .deletingLastPathComponent()
                                    .deletingLastPathComponent()
                                NSWorkspace.shared.open(appBundleURL)
                            } else {
                                self.authError = "ES extension did not approve"
                            }
                        }
                    }
                } else {
                    DispatchQueue.main.async {
                        self.authError = "Authentication failed"
                    }
                }
            }
        }
    }
}
