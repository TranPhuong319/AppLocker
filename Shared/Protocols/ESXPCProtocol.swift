//
//  ESXPCProtocol.swift
//  AppLocker
//
//  Created by Doe Phương on 26/9/25.
//

import Foundation

@objc public protocol ESXPCProtocol {
    func notifyBlockedExec(name: String, path: String, sha: String)
}
