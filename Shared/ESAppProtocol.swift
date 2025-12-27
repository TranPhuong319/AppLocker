//
//  ESAppProtocol.swift
//  AppLocker
//
//  Created by Doe Phương on 27/9/25.
//
//  EN: XPC protocol for the host app to talk to the ES extension.
//  VI: Giao thức XPC để ứng dụng chính giao tiếp với extension ES.
//

import Foundation

@objc public protocol ESAppProtocol {
    // EN: App -> Extension: temporarily allow a SHA (reply: Bool acknowledgment).
    // VI: App -> Extension: cho phép tạm thời một SHA (trả về Bool xác nhận).
    func allowSHAOnce(_ sha: String, withReply reply: @escaping (Bool) -> Void)

    // EN: App -> Extension: update the blocked apps list (NSArray of NSDictionary).
    // VI: App -> Extension: cập nhật danh sách ứng dụng bị khóa (NSArray của NSDictionary).
    func updateBlockedApps(_ apps: NSArray)

    // EN: App -> Extension: request temporary access to config.plist.
    // VI: App -> Extension: yêu cầu quyền truy cập tạm thời vào config.plist.
    func allowConfigAccess(_ pid: Int32, withReply reply: @escaping (Bool) -> Void)

    // EN: App -> Extension: update preferred language for the extension process.
    // VI: App -> Extension: cập nhật ngôn ngữ ưu tiên cho tiến trình extension.
    func updateLanguage(to code: String)
}
