//
//  ESXPCProtocol.swift
//  AppLocker
//
//  Created by Doe Phương on 26/9/25.
//
//  EN: XPC protocol for notifications from the ES extension to the host app.
//  VI: Giao thức XPC để extension ES gửi thông báo tới ứng dụng chính.
//

import Foundation

@objc public protocol ESXPCProtocol {
    // EN: Extension -> App: notify that an execution was blocked (fire-and-forget).
    // VI: Extension -> App: thông báo một lần thực thi bị chặn (không cần phản hồi).
    func notifyBlockedExec(name: String, path: String, sha: String)
}
