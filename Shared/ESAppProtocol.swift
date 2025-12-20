//
//  ESAppProtocol.swift
//  AppLocker
//
//  Created by Doe Phương on 27/9/25.
//

import Foundation

@objc public protocol ESAppProtocol {
    // App -> Extension: ask extension to temporarily allow a SHA (extension replies with Bool ack)
    func allowSHAOnce(_ sha: String, withReply reply: @escaping (Bool) -> Void)

    // App -> Extension: update blocked apps list (NSArray of NSDictionary)
    func updateBlockedApps(_ apps: NSArray)
    
    // App -> Extension: request access to config.plist
    func allowConfigAccess(_ pid: Int32, withReply reply: @escaping (Bool) -> Void)
    
    // App -> Extension: Send language
    func updateLanguage(to code: String)
}
