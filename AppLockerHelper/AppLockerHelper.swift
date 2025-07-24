//
//  AppLockerHelper.swift
//  AppLocker
//
//  Created by Doe Phương on 24/07/2025.
//


import Foundation
import ServiceManagement

class AppLockerHelper: NSObject, AppLockerHelperProtocol {
    func performAdminTask(_ task: String, withReply: @escaping (Bool, String) -> Void) {
        // task là một chuỗi JSON hoặc định dạng khác chứa thông tin về tác vụ
        // Ví dụ: di chuyển file, thay đổi quyền, v.v.
        do {
            let components = task.components(separatedBy: "|")
            guard components.count >= 3 else {
                withReply(false, "Invalid task format")
                return
            }

            let operation = components[0]
            let sourcePath = components[1]
            let destPath = components[2]

            switch operation {
            case "move":
                try FileManager.default.moveItem(atPath: sourcePath, toPath: destPath)
            case "copy":
                try FileManager.default.copyItem(atPath: sourcePath, toPath: destPath)
            case "chmod":
                try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: destPath)
            case "remove":
                try FileManager.default.removeItem(atPath: destPath)
            default:
                withReply(false, "Unknown operation")
                return
            }
            withReply(true, "")
        } catch {
            withReply(false, error.localizedDescription)
        }
    }
}
