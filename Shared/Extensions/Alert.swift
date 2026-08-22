//
//  Alert.swift
//  AppLocker
//
//  Created by Doe Phương on 16/9/25.
//

import AppKit

/// Kết quả trả về sau khi hiển thị Alert
enum AlertResult {
    case button(index: Int, title: String) // Người dùng bấm nút nào đó
    case cancelled                         // Người dùng hủy (Cancel, ESC, đóng bằng X)
}

enum AlertShow {
    /// Hiển thị Alert với nhiều nút (tối đa 3)
    /// - Nếu có window đang hiển thị và ứng dụng đang active → hiện dạng sheet
    /// - Nếu không có window active → hiện modal thường
    /// - Parameters:
    ///   - title: Tiêu đề
    ///   - message: Nội dung
    ///   - style: Kiểu alert (critical, warning, informational)
    ///   - buttons: Danh sách nút
    /// - Returns: `AlertResult` để switch xử lý
    @discardableResult
    static func show(
        title: String,
        message: String,
        style: NSAlert.Style,
        buttons: [String],
        cancelIndex: Int? = nil,
        destructiveIndex: Int? = nil,
        defaultIndex: Int? = nil
    ) -> AlertResult {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = style

        let displayedButtons = Array(buttons.prefix(3))
        for (index, buttonTitle) in displayedButtons.enumerated() {
            let button = alert.addButton(withTitle: buttonTitle)

            if index == defaultIndex {
                button.keyEquivalent = "\r"
            } else if index == cancelIndex {
                button.keyEquivalent = "\u{1b}"
            } else {
                button.keyEquivalent = ""
            }
        }

        NSApplication.shared.activate()
        let response = runAlert(alert)

        let index: Int
        switch response {
        case .alertFirstButtonReturn:  index = 0
        case .alertSecondButtonReturn: index = 1
        case .alertThirdButtonReturn:  index = 2
        default:
            return .cancelled
        }

        if index == cancelIndex {
            return .cancelled
        }

        return .button(index: index, title: displayedButtons[index])
    }

    /// Hiển thị Alert đơn giản chỉ có 1 nút OK
    static func showInfo(
        title: String,
        message: String,
        style: NSAlert.Style = .informational
    ) {
        _ = show(title: title, message: message, style: style, buttons: ["OK"])
    }

    /// Chạy alert: chỉ gắn dạng sheet khi có window thực thụ (không phải menu bar/status bar),
    /// ngược lại hiện modal độc lập
    @discardableResult
    private static func runAlert(_ alert: NSAlert) -> NSApplication.ModalResponse {
        let candidateWindows = [NSApp.keyWindow, NSApp.mainWindow].compactMap { $0 } + NSApp.windows
        if let window = candidateWindows.first(where: isValidSheetWindow) {
            var modalResponse: NSApplication.ModalResponse = .alertFirstButtonReturn
            alert.beginSheetModal(for: window) { response in
                modalResponse = response
                NSApp.stopModal(withCode: response)
            }
            _ = NSApp.runModal(for: alert.window)
            return modalResponse
        } else {
            return alert.runModal()
        }
    }

    private static func isValidSheetWindow(_ window: NSWindow) -> Bool {
        guard window.isVisible, !window.isMiniaturized else { return false }
        if window.className.contains("StatusBar") || window.className.contains("Menu") { return false }
        if window.level == .statusBar || window.level == .popUpMenu || window.level == .mainMenu { return false }
        return window.styleMask.contains(.titled)
    }
}
