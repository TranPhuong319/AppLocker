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
    func registerAgentWithoutImmediateLaunch() {
        #if DEBUG
        Logfile.core.info("Skipping registerAgentWithoutImmediateLaunch in DEBUG mode")
        #else
        manageAgent(plistName: plistName, action: .install)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["stop", plistName]
        try? process.run()
        #endif
    }

    @discardableResult
    func manageAgent(
        plistName: String,
        action: AgentAction
    ) -> AgentManageResult {
        #if DEBUG
        Logfile.core.info("Skipping agent manage in DEBUG mode")
        return .alreadyInstalled
        #else
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
                    Logfile.core.info("Agent status: enabled")
                    return .alreadyInstalled
                } else {
                    Logfile.core.info("Agent status: disabled")
                    return .alreadyUninstalled
                }
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
        #endif
    }

    @discardableResult
    func checkAgentStatus() -> Bool {
        let result = manageAgent(plistName: plistName, action: .check)
        switch result {
        case .installed, .alreadyInstalled:
            return true
        default:
            return false
        }
    }

    @discardableResult
    func repairAgentService() -> Bool {
        let result = manageAgent(plistName: plistName, action: .install)
        switch result {
        case .installed, .alreadyInstalled:
            return true
        default:
            return false
        }
    }
}
