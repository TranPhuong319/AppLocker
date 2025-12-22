//
//  LockedAppConfig.swift
//  AppLocker
//
//  Created by Doe Phương on 27/9/25.
//
//  EN: Encodes configuration for a locked application.
//  VI: Cấu hình mã hóa cho một ứng dụng bị khóa.
//

import Foundation

struct LockedAppConfig: Codable, Hashable {
    let bundleID: String
    let path: String
    var sha256: String
    let blockMode: String  // EN: "Launcher" or "ES". VI: "Launcher" hoặc "ES".
    let execFile: String?  // EN: Executable file name in Contents/MacOS/. VI: Tên file thực thi trong Contents/MacOS/.
    let name: String?      // EN: Display name. VI: Tên hiển thị.

    enum CodingKeys: String, CodingKey {
        case bundleID, path, sha256, blockMode, execFile, name
    }
}

extension LockedAppConfig {
    // EN: Convert to a simple dictionary for XPC transfer.
    // VI: Chuyển sang dictionary đơn giản để truyền qua XPC.
    func toDict() -> [String: String] {
        return ["bundleID": bundleID, "path": path, "sha256": sha256]
    }
}
