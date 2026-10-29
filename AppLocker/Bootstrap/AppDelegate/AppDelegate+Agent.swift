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
    var isAgentActive: Bool {
        SMAppService.agent(plistName: "\(Self.plistName).plist").status == .enabled
    }

    var isLaunchedByLaunchd: Bool {
        ProcessInfo.processInfo.environment["LAUNCHED_BY_LAUNCHD"] == "1"
    }

    func registerAgentWithoutImmediateLaunch() {
        #if DEBUG
        Logfile.app.debug("[Agent] Skipping registerAgentWithoutImmediateLaunch in DEBUG mode")
        #else
        manageAgent(action: .install)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["stop", Self.plistName]
        do {
            try process.run()
        } catch {
            Logfile.app.error(
                "[Agent] Failed to stop agent via launchctl: \(error.localizedDescription, privacy: .public)"
            )
        }
        #endif
    }

    @discardableResult
    func manageAgent(
        plistName: String = AppDelegate.plistName,
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
                if agent.status == .enabled {
                    Logfile.app.debug("[Agent] Agent already enabled")
                    return .alreadyInstalled
                }
                try agent.register()
                Logfile.app.info("[Agent] Agent registered successfully")
                return .installed

            case .uninstall:
                if agent.status != .enabled {
                    Logfile.app.debug("[Agent] Agent already disabled")
                    return .alreadyUninstalled
                }
                try agent.unregister()
                Logfile.app.info("[Agent] Agent unregistered successfully")
                return .uninstalled

            case .check:
                let active = isAgentActive
                Logfile.app.debug("[Agent] Agent status: \(active ? "enabled" : "disabled", privacy: .public)")
                return active ? .alreadyInstalled : .alreadyUninstalled
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
    func forceReRegisterAgent(plistName: String = AppDelegate.plistName) -> Bool {
        #if DEBUG
        Logfile.app.debug("[Agent] Skipping forceReRegisterAgent in DEBUG mode")
        return true
        #else
        let agent = SMAppService.agent(plistName: "\(plistName).plist")
        Logfile.app.info("[Agent] Force re-registering agent to reset launchd state...")
        do {
            try? agent.unregister()
            try agent.register()
            let statusDesc = agent.status.description
            Logfile.app.notice("[Agent] Force re-register succeeded. Status: \(statusDesc, privacy: .public)")
            return agent.status == .enabled
        } catch {
            Logfile.app.error("[Agent] Force re-register failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
        #endif
    }

    func runLaunchctlKickstart(timeout: Duration = .seconds(3)) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["kickstart", "-k", "gui/\(getuid())/\(Self.plistName)"]
        do {
            try process.run()
        } catch {
            Logfile.app.error("[Bootstrap] Failed to run launchctl: \(error.localizedDescription, privacy: .public)")
            return false
        }

        let start = ContinuousClock.now
        while process.isRunning && ContinuousClock.now - start < timeout {
            usleep(50_000) // 50ms
        }

        if process.isRunning {
            Logfile.app.warning("[Bootstrap] launchctl kickstart timed out after 3s. Terminating command.")
            process.terminate()
            return false
        }

        return process.terminationStatus == 0
    }

    @discardableResult
    func checkAgentStatus() -> Bool {
        isAgentActive
    }

    @discardableResult
    func repairAgentService() -> Bool {
        let result = manageAgent(action: .install)
        switch result {
        case .installed, .alreadyInstalled:
            return true
        default:
            openSystemSettingsForExtension()
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
