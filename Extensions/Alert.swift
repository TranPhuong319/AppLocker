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

final class AlertShow {
    /// Hiển thị Alert với nhiều nút (tối đa 3)
    /// - Parameters:
    ///   - title: Tiêu đề
    ///   - message: Nội dung
    ///   - style: Kiểu alert (critical, warning, informational)
    ///   - buttons: Danh sách nút (nút cuối luôn là Cancel)
    /// - Returns: `AlertResult` để switch xử lý
    @discardableResult
    static func show(
        title: String,
        message: String,
        style: NSAlert.Style,
        buttons: [String],
        cancelIndex: Int? = nil
    ) -> AlertResult {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = style

        // NSAlert chỉ hỗ trợ tối đa 3 nút
        let displayedButtons = Array(buttons.prefix(3))
        displayedButtons.forEach { alert.addButton(withTitle: $0) }

        // Xác định vị trí cancel
        let effectiveCancelIndex: Int? = {
            if let cancelIndex, cancelIndex >= 0, cancelIndex < displayedButtons.count {
                return cancelIndex
            }
            return displayedButtons.isEmpty ? nil : displayedButtons.count - 1
        }()

        NSApplication.shared.activate(ignoringOtherApps: true)
        let response = alert.runModal()

        let index: Int
        switch response {
        case .alertFirstButtonReturn:  index = 0
        case .alertSecondButtonReturn: index = 1
        case .alertThirdButtonReturn:  index = 2
        default:
            return .cancelled
        }

        if index == effectiveCancelIndex {
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
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = style
        alert.addButton(withTitle: "OK")

        NSApplication.shared.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
