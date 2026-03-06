//
//  LockManagerProtocol.swift
//  AppLocker
//
//  Created by Doe Phương on 27/9/25.
//

import Foundation
import AppKit

protocol LockManagerProtocol: ObservableObject {
    var lockedApps: [String: LockedAppConfig] { get set }
    var allApps: [InstalledApp] { get set }

    func toggleLock(for paths: [String])
    func reloadAllApps()
    func isLocked(path: String) -> Bool
}
