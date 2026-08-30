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
    func isAgentLoadedInLaunchd() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["print", "gui/\(getuid())/\(plistName)"]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    func registerAgentWithoutImmediateLaunch() {
        #if DEBUG
        Logfile.app.debug("[Agent] Skipping registerAgentWithoutImmediateLaunch in DEBUG mode")
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
        Logfile.app.debug("[Agent] Skipping agent manage in DEBUG mode")
        return .alreadyInstalled
        #else
        let agent = SMAppService.agent(plistName: "\(plistName).plist")

        do {
            switch action {

            case .install:
                if isAgentLoadedInLaunchd() {
                    Logfile.app.debug("[Agent] Agent already enabled in launchd")
                    return .alreadyInstalled
                }
                if agent.status == .enabled {
                    try? agent.unregister()
                }
                try agent.register()
                Logfile.app.info("[Agent] Agent registered successfully")
                return .installed

            case .uninstall:
                if agent.status != .enabled && !isAgentLoadedInLaunchd() {
                    Logfile.app.debug("[Agent] Agent already disabled")
                    return .alreadyUninstalled
                }
                try agent.unregister()
                Logfile.app.info("[Agent] Agent unregistered successfully")
                return .uninstalled

            case .check:
                if agent.status == .enabled && isAgentLoadedInLaunchd() {
                    Logfile.app.debug("[Agent] Agent status: enabled")
                    return .alreadyInstalled
                } else {
                    Logfile.app.debug("[Agent] Agent status: disabled")
                    return .alreadyUninstalled
                }
            }

        } catch {
            let nsError = error as NSError
            Logfile.app.error(
                """
                [Agent] Agent manage failed: \(nsError.domain) \
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
            SMAppService.openSystemSettingsLoginItems()
            AlertShow.showInfo(
                title: String(localized: "Enable Background Service"),
                message: String(
                    localized: "macOS requires enabling AppLocker in System Settings -> Login Items & Extensions."
                ),
                style: .informational
            )
            return false
        }
    }
}
