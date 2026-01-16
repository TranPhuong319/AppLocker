//
//  AppDelegate+Launchctl.swift
//  AppLocker
//
//  Created by Doe Phương on 16/1/26.
//

import Foundation

extension AppDelegate {
    func launchedByLaunchd() -> Bool {
        guard let launchByLaunchctl = ProcessInfo.processInfo.environment[
            "LAUNCHED_BY_LAUNCHD"
        ] else {
            return false
        }
        return launchByLaunchctl == "1"
    }
}
