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
    /// - Nếu có window chính đang hiển thị → hiện dạng sheet
    /// - Nếu không có window → hiện modal thường
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
        let response = runAlert(alert)

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
        runAlert(alert)
    }

    // MARK: - Private

    /// Chạy alert: nếu có window chính đang hiển thị → sheet, ngược lại → modal
    @discardableResult
    private static func runAlert(_ alert: NSAlert) -> NSApplication.ModalResponse {
        if let window = NSApp.keyWindow ?? NSApp.mainWindow,
           window.isVisible {
            // Hiển thị dạng sheet trên window chính
            var response: NSApplication.ModalResponse = .alertFirstButtonReturn
            var completed = false

            alert.beginSheetModal(for: window) { result in
                response = result
                completed = true
                NSApp.stopModal()
            }

            // Chờ đồng bộ cho đến khi sheet đóng
            if !completed {
                NSApp.runModal(for: window)
            }

            return response
        } else {
            // Không có window → hiện modal thường
            return alert.runModal()
        }
    }
}
