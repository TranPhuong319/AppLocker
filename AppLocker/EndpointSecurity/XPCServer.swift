//
//  XPCServer.swift
//  AppLocker
//
//  Created by Doe Phương on 27/9/25.
//

import AppKit
import Foundation
import os

// MARK: - Pure IPC Receiver
@MainActor
final class XPCServer: NSObject, ESXPCProtocol {
    nonisolated static let shared = XPCServer()

    nonisolated override init() { super.init() }

    nonisolated func notifyBlockedExec(name: String, path: String, cdhash: String, pid: Int32) {
        Logfile.appXPC.notice(
            "[Auth] Blocked: \(name, privacy: .public), PID: \(pid, privacy: .public), Path: \(path, privacy: .public)"
        )

        Task { @MainActor in
            AuthCoordinator.shared.handleBlockedExec(name: name, path: path, cdhash: cdhash, pid: pid)
        }
    }

    nonisolated func notifyProcessExited(pid: Int32) {
        Task { @MainActor in
            AuthCoordinator.shared.handleProcessExited(pid: pid)
        }
    }
}
