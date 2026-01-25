//
//  AppDelegate+LoginItems.swift
//  AppLocker
//
//  Created by Doe Phương on 15/1/26.
//

import Foundation
import ServiceManagement

enum LoginItemAction {
    case install
    case uninstall
}

enum LoginItemManageResult {
    case installed
    case uninstalled
    case alreadyInstalled
    case alreadyUninstalled
    case failed(Error)
}

extension AppDelegate {
    @discardableResult
    func manageHelperLoginItem(
        helperBundleID: String,
        action: LoginItemAction
    ) -> LoginItemManageResult {

        let service = SMAppService.loginItem(identifier: helperBundleID)

        do {
            switch action {

            case .install:
                if service.status == .enabled {
                    return .alreadyInstalled
                }
                try service.register()
                return .installed

            case .uninstall:
                if service.status != .enabled {
                    return .alreadyUninstalled
                }
                try service.unregister()
                return .uninstalled
            }

        } catch {
            return .failed(error)
        }
    }
}
