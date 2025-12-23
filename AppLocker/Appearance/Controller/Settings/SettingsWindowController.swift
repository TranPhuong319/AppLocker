//
//  SettingsWindowController.swift
//  AppLocker
//
//  Created by Doe Phương on 26/8/25.
//

import SwiftUI
import AppKit

class SettingsWindowController: NSWindowController, NSWindowDelegate {
    static var shared: SettingsWindowController?

    // EN: Show the settings window.
    // VI: Hiển thị cửa sổ cài đặt.
    static func show() {
        // 1. Nếu cửa sổ đã tồn tại, đưa nó lên phía trước
        if let controller = shared {
            controller.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        // 2. Sử dụng NSHostingController thay vì NSHostingView
        let contentView = SettingsView()
        let hostingController = NSHostingController(rootView: contentView)
        
        // 3. Khởi tạo cửa sổ với contentViewController
        // Việc dùng contentViewController giúp Window tự động khớp với intrinsicContentSize của SwiftUI view
        let window = NSWindow(contentViewController: hostingController)
        
        // Cấu hình Style Mask
        window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        window.backingType = .buffered
        window.title = "Settings".localized
        window.standardWindowButton(.zoomButton)?.isHidden = true
        
        // 4. Thiết lập kích thước mặc định (nếu SwiftUI view không xác định kích thước cố định)
        window.setContentSize(NSSize(width: 500, height: 400))
        window.center()
        
        // 5. Quản lý instance
        let controller = SettingsWindowController(window: window)
        window.delegate = controller
        shared = controller

        // 6. Hiển thị
        NSApp.activate(ignoringOtherApps: true)
        controller.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
    }

    // MARK: - NSWindowDelegate
    
    func windowWillClose(_ notification: Notification) {
        // Giải phóng bộ nhớ khi đóng cửa sổ
        SettingsWindowController.shared = nil
    }
}
