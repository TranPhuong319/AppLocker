//
//  AppUpdater.swift
//  AppLocker
//
//  Created by Doe Phương on 26/8/25.
//

import Foundation
import Sparkle

class AppUpdater: NSObject {
    static let shared = AppUpdater()

    let updaterController: SPUStandardUpdaterController

    private override init() {
        self.updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        super.init()

    }

    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }

    func gentleReminder() {
        updaterController.updater.resetUpdateCycle()
    }
}
