//
//  ESXPCProtocol.swift
//  AppLocker
//
//  Created by Doe Phương on 26/9/25.
//

import Foundation

@objc public protocol ESXPCProtocol {
    // Extension -> App: notify that an exec was blocked (no reply required).
    // pid: process id of attempted exec
    func notifyBlockedExec(name: String, path: String, sha: String)
}
