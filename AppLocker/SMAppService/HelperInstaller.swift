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
    // MARK: - Kiểm tra trạng thái đăng ký app chính
    static func appRegistrationStatus() -> SMAppService.Status {
        return SMAppService.mainApp.status
    }
    
    // MARK: - Kiểm tra helper, nếu chưa enable → tự cài + hiển thị alert
    @discardableResult
    static func checkAndAlertBlocking(helperToolIdentifier: String) -> Bool {
        while true {
            let helperStatus = manageHelperTool(action: .none, helperToolIdentifier: helperToolIdentifier)
            
            switch helperStatus {
            case .enabled:
                return true
                
            case .requiresApproval:
                requiresApprovalAlert()
                
            default:
                // Chưa cài → thử install
                let status = manageHelperTool(action: .install, helperToolIdentifier: helperToolIdentifier)
                if status == .requiresApproval {
                    requiresApprovalAlert()
                }
            }
            
            // tránh loop nhanh → delay nhẹ
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        }
    }
    
    // MARK: - Cài đặt / gỡ bỏ / kiểm tra Helper Tool
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
                Logfile.core.error("Failed to install helper: \(error.localizedDescription)")
                return .notRegistered
            }
            
        case .uninstall:
            Task {
                do {
                    try await service.unregister()
                    Logfile.core.info("Helper unregistered and killed successfully")
                } catch {
                    Logfile.core.error("Failed to unregister helper: \(error.localizedDescription)")
                }
            }
            return service.status
            
        case .none:
            return service.status
        }
    }
    
    // MARK: - Alert khi helper cần bật trong System Settings
    static func requiresApprovalAlert() {
        let result = AlertShow.show(
            title: "Helper has not turned on".localized,
            message: "Helper Tool has registered but needs to turn on System Settings > Login Items.".localized,
            style: .critical,
            buttons: ["Retry".localized, "Quit AppLocker".localized])
        switch result {
        case .button: SMAppService.openSystemSettingsLoginItems()
        case .cancelled: NSApp.terminate(nil)
        }
    }
}

