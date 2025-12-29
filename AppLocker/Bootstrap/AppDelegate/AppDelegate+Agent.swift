//
//  AppDelegate+Agent.swift
//  AppLocker
//
//  Created by Doe Phương on 28/12/25.
//

import ServiceManagement
import AppKit
import Foundation

extension AppDelegate {
    func manageAgent(plistName: String, action: AgentAction) {
        let agent = SMAppService.agent(plistName: "\(plistName).plist")

        do {
            switch action {
            case .install:
                if agent.status == .enabled {
                    Logfile.core.info("Agent already registered: \(agent.status.description)")
                    return
                }
                try agent.register()
                Logfile.core.info("Agent registered successfully")

            case .uninstall:
                if agent.status == .enabled {
                    try agent.unregister()
                    Logfile.core.info("Agent unregistered successfully")
                } else {
                    Logfile.core.info("Agent not registered, skipping uninstall")
                }

            case .checkAndInstallifNeed:
                if agent.status != .enabled {
                    Logfile.core.info("Agent not active, registering new one")
                    try agent.register()
                    NSApp.terminate(nil)
                }
            }

        } catch {
            let nsError = error as NSError
            Logfile.core.error(
                """
                Failed to manage agent: \(nsError.domain) - \
                code: \(nsError.code) - \(nsError.localizedDescription)
                """
            )
        }
    }
}
