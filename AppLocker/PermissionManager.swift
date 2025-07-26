//
//  PermissionManager.swift
//  AppLocker
//
//  Created by Doe Phương on 25/07/2025.
//


//
//  PermissionManager.swift
//  AppLocker
//
//  Created by Doe Phương on 25/07/2025.
//

import Foundation
import Security
import AppKit

class PermissionManager {
    /// Gọi hàm này khi cần nâng quyền (ví dụ: chmod, xóa file hệ thống, v.v.)
    static func requestAuthorization(reason: String = "Ứng dụng cần quyền nâng cao để tiếp tục") -> AuthorizationRef? {
        var authRef: AuthorizationRef?
        let authFlags: AuthorizationFlags = [.interactionAllowed, .extendRights, .preAuthorize]

        let status = AuthorizationCreate(nil, nil, authFlags, &authRef)

        guard status == errAuthorizationSuccess, let ref = authRef else {
            logAndAlert(errorCode: status, context: "AuthorizationCreate")
            return nil
        }

        let rights = AuthorizationRights(count: 0, items: nil)

        let copyStatus = AuthorizationCopyRights(ref, &rights, nil, authFlags, nil)
        guard copyStatus == errAuthorizationSuccess else {
            logAndAlert(errorCode: copyStatus, context: "AuthorizationCopyRights")
            return nil
        }

        return ref
    }

    /// Hiển thị alert và ghi log khi có lỗi
    private static func logAndAlert(errorCode: OSStatus, context: String) {
        let description = authorizationStatusDescription(errorCode)
        let message = "[PermissionManager] Lỗi tại \(context): OSStatus = \(errorCode) (\(description))"
        
        print(message)
        logToFile(message)
        showAlert(message: message)
    }

    /// Mô tả mã lỗi OSStatus
    private static func authorizationStatusDescription(_ code: OSStatus) -> String {
        switch code {
        case errAuthorizationCanceled:
            return "Người dùng đã huỷ"
        case errAuthorizationDenied:
            return "Từ chối truy cập"
        case errAuthorizationInteractionNotAllowed:
            return "Không cho phép tương tác người dùng"
        case errAuthorizationInvalidRef:
            return "AuthorizationRef không hợp lệ"
        case errAuthorizationInvalidSet:
            return "AuthorizationRights không hợp lệ"
        default:
            return "Không rõ lỗi – mã OSStatus: \(code)"
        }
    }

    /// Ghi log vào file: ~/Library/Logs/AppLocker.log
    private static func logToFile(_ message: String) {
        let fileManager = FileManager.default
        let logDir = fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs")
        let logFile = logDir.appendingPathComponent("AppLocker.log")

        let timestamp = ISO8601DateFormatter().string(from: Date())
        let fullMessage = "\(timestamp) \(message)\n"

        if !fileManager.fileExists(atPath: logFile.path) {
            try? fullMessage.write(to: logFile, atomically: true, encoding: .utf8)
        } else {
            if let handle = try? FileHandle(forWritingTo: logFile) {
                handle.seekToEndOfFile()
                if let data = fullMessage.data(using: .utf8) {
                    handle.write(data)
                }
                handle.closeFile()
            }
        }
    }

    /// Hiện cảnh báo người dùng
    private static func showAlert(message: String) {
        let alert = NSAlert()
        alert.messageText = "Lỗi nâng quyền"
        alert.informativeText = message
        alert.alertStyle = .critical
        alert.runModal()
    }
}
