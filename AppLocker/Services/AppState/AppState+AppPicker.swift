//
//  AppState+AppPicker.swift
//  AppLocker
//
//  Created by Doe Phương on 16/8/26.
//

import AppKit
import Foundation
import UniformTypeIdentifiers

extension AppState {
    func addOthersApp(over window: NSWindow? = nil) {
        let panel = NSOpenPanel()
        panel.delegate = self
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.applicationBundle]
        panel.message = String(localized: "Select the application to lock")
        panel.prompt = String(localized: "Lock")

        if let window {
            panel.beginSheetModal(for: window) { [weak self] response in
                if response == .OK {
                    self?.processSelectedPaths(panel.urls.map { $0.path })
                }
            }
        } else {
            if panel.runModal() == .OK {
                processSelectedPaths(panel.urls.map { $0.path })
            }
        }
    }

    func processSelectedPaths(_ paths: [String]) {
        let pathsSet = Set(paths)
        if !pathsSet.isEmpty {
            toggleLockPopup(for: pathsSet, locking: true)
        }
    }

    // MARK: - NSOpenSavePanelDelegate
    func panel(_ sender: Any, shouldEnable url: URL) -> Bool {
        let path = url.path

        // 1. Chặn chính app đang chạy (Dùng cache O(1))
        if path == selfBundlePath || url.lastPathComponent == selfBundleName {
            return false
        }

        // 2. Kiểm tra danh sách đã khóa (O(1) thay vì O(n))
        if manager.lockedApps[path] != nil {
            return false
        }

        // 3. Chặn các thư mục hệ thống nhạy cảm (Tối ưu hóa string prefix)
        if path.hasPrefix("/System/") {
            // Chỉ cho phép duyệt trong /System/Applications/
            if !path.hasPrefix("/System/Applications/") {
                return false
            }
        }

        return true
    }
}
