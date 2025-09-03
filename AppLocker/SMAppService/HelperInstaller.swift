//
//  HelperInstaller.swift
//  AppLocker
//
//  Created by Doe Phương on 28/8/25.
//

import AppKit
import ServiceManagement

enum HelperToolAction {
    case install, uninstall, none
}

struct HelperInstaller {
    // MARK: - Kiểm tra trạng thái đăng ký app

    static func appRegistrationStatus() -> SMAppService.Status {
        return SMAppService.mainApp.status
    }

    // MARK: - Hiện alert nếu chưa đăng ký

    static func showAlert(title: String, message: String,
                          okButton: String, skipButton: String,
                          onConfirm: (() -> Void)? = nil) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: okButton)
        alert.addButton(withTitle: skipButton)
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            onConfirm?()
        } else {
            Logfile.core.info("Quit Application")
            NSApp.terminate(nil)
        }
    }

    // MARK: - Kiểm tra + hiển thị alert tự động
    @discardableResult
    static func checkAndAlertBlocking(helperToolIdentifier: String) -> Bool {
        while true {
            let helperStatus = manageHelperTool(action: .none, helperToolIdentifier: helperToolIdentifier)

            switch helperStatus {
            case .enabled:
                return true

            case .requiresApproval:
                requiresApprovalAlent()

            default:
                // Chưa cài → thử install
                let status = manageHelperTool(action: .install, helperToolIdentifier: helperToolIdentifier)
                if status == .requiresApproval {
                    // Alert đồng bộ, block flow
                    requiresApprovalAlent()
                }
            }

            // Delay nhỏ để tránh loop quá nhanh
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        }
    }

    // MARK: - Quản lý Helper Tool

    static func manageHelperTool(action: HelperToolAction = .none,
                                 helperToolIdentifier: String) -> SMAppService.Status {
        let plistName = "\(helperToolIdentifier).plist"
        let service = SMAppService.daemon(plistName: plistName)

        switch action {
        case .install:
            do {
                try service.register()
                return service.status
            } catch {
                return .requiresApproval // hoặc default lỗi
            }
        case .uninstall:
            try? service.unregister()
            return service.status
        case .none:
            return service.status
        }
    }

    static func requiresApprovalAlent() {
        showAlert(title: NSLocalizedString("Helper has not turned on", comment: "").localized,
                  message: "Helper Tool has registered but needs to turn on System Settings > Login Items.".localized,
                  okButton: "Retry".localized,
                  skipButton: "Quit AppLocker".localized) {
            SMAppService.openSystemSettingsLoginItems()
        }
    }
}
