//
//  WindowLayout.swift
//  AppLocker
//
//  Created by Doe Phương on 16/2/26.
//

import Foundation

/// Single source of truth cho tất cả kích thước window và sheet trong app.
/// Khi cần thay đổi kích thước, chỉ cần sửa ở đây.
enum WindowLayout {
    enum Main {
        static let size = NSSize(width: 450, height: 470)
    }

    enum Welcome {
        static let size = NSSize(width: 350, height: 450)
    }

    enum Sheet {
        enum AddApp {
            static let minSize = NSSize(width: 400, height: 500)
            static let listMaxHeight: CGFloat = 420
        }

        enum DeleteQueue {
            static let minSize = NSSize(width: 350, height: 370)
        }

        enum LockingPopup {
            static let minSize = NSSize(width: 200, height: 100)
        }
    }
}
