//
//  AppDelegate+Agent.swift
//  AppLocker
//
//  Created by Doe Phương on 28/12/25.
//

import ServiceManagement
import AppKit
import Foundation

enum AgentManageResult {
    case installed
    case uninstalled
    case alreadyInstalled
    case alreadyUninstalled
    case failed(Error)
}

extension AppDelegate {
    @discardableResult
    func manageAgent(
        plistName: String,
        action: AgentAction
    ) -> AgentManageResult {

        let agent = SMAppService.agent(plistName: "\(plistName).plist")

        do {
            switch action {

            case .install:
                if agent.status == .enabled {
                    Logfile.core.info("Agent already enabled")
                    return .alreadyInstalled
                }
                try agent.register()
                Logfile.core.info("Agent registered")
                return .installed

            case .uninstall:
                if agent.status != .enabled {
                    Logfile.core.info("Agent already disabled")
                    return .alreadyUninstalled
                }
                try agent.unregister()
                Logfile.core.info("Agent unregistered")
                return .uninstalled

            case .check:
                if agent.status == .enabled {
                    Logfile.core.info("Agent already enabled")
                    return .alreadyInstalled
                }
                try agent.register()
                Logfile.core.info("Agent registered")
                return .installed
            }

        } catch {
            let nsError = error as NSError
            Logfile.core.error(
                """
                Agent manage failed: \(nsError.domain) \
                \(nsError.code) \
                \(nsError.localizedDescription)
                """
            )
            return .failed(error)
        }
    }
}
