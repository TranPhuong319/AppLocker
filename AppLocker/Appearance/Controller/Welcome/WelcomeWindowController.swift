//
//  WelcomeWindowController.swift
//  AppLocker
//
//  Created by Doe Phương on 27/9/25.
//

import SwiftUI
import AppKit

class WelcomeWindowController: NSWindowController, NSWindowDelegate {
    static var shared: WelcomeWindowController?

    // EN: Show the welcome window.
    // VI: Hiển thị cửa sổ chào mừng khi khởi chạy ứng dụng.
    static func show() {
        if let controller = shared {
            controller.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        // 1. Sử dụng NSHostingController để quản lý SwiftUI View
        let contentView = WelcomeView()
        let hostingController = NSHostingController(rootView: contentView)
        
        // 2. Khởi tạo cửa sổ
        // Sử dụng .fullSizeContentView để nội dung tràn lên thanh tiêu đề cho đẹp hơn
        let window = NSWindow(contentViewController: hostingController)
        window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        window.backingType = .buffered
        window.title = "Welcome to AppLocker".localized
        window.titlebarAppearsTransparent = true // Làm thanh tiêu đề trong suốt
        window.titleVisibility = .hidden        // Ẩn tiêu đề văn bản (vì Welcome thường dùng logo/text to bên trong view)

        // 3. Thiết lập kích thước cố định
        let fixedSize = NSSize(width: 350, height: 450)
        window.setContentSize(fixedSize)
        window.minSize = fixedSize
        window.maxSize = fixedSize // Không cho phép resize cửa sổ welcome
        
        window.center()

        // Ẩn các nút không cần thiết
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true

        let controller = WelcomeWindowController(window: window)
        window.delegate = controller
        shared = controller
        
        // 4. Kích hoạt App và hiển thị cửa sổ
        NSApp.activate(ignoringOtherApps: true)
        controller.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
    }

    // MARK: - NSWindowDelegate
    
    func windowWillClose(_ notification: Notification) {
        // EN: If the welcome window is closed, terminate the app (common for onboarding).
        // VI: Nếu cửa sổ chào mừng bị đóng, thoát ứng dụng (thường dùng cho luồng bắt buộc).
        WelcomeWindowController.shared = nil
        NSApp.terminate(nil)
    }
}
