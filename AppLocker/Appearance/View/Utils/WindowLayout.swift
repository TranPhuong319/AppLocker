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
    struct Main {
        static let size = NSSize(width: 450, height: 470)
    }

    struct Welcome {
        static let size = NSSize(width: 660, height: 480)
    }

    struct AddApp {
        static let minSize = NSSize(width: 400, height: 500)
        static let listMaxHeight: CGFloat = 420
    }

    struct DeleteQueue {
        static let minSize = NSSize(width: 350, height: 370)
    }

    struct LockingPopup {
        static let minSize = NSSize(width: 200, height: 100)
    }

    struct BatchAuth {
        static let size = NSSize(width: 440, height: 360)
        static let maxListHeight: CGFloat = 220
    }

    struct About {
        static let size = NSSize(width: 450, height: 220)
    }
}
