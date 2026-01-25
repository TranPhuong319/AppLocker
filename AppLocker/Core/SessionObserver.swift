//
//  SessionObserver.swift
//  AppLocker
//
//  Created by Doe Phương on 10/12/25.
//

import Cocoa

final class SessionObserver {

    private var observers: [NSObjectProtocol] = []
    static let shared = SessionObserver()
    let manager = AppState.shared.manager

    func start() {

        func handleDeactive() {
            DispatchQueue.global().async {
                ESXPCClient.shared.updateBlockedApps([])
            }
        }

        func handleActive() {
            let lockedAppsList = manager.lockedApps.values.map { $0.toDict() }
            DispatchQueue.global().async {
                ESXPCClient.shared.updateBlockedApps(lockedAppsList)
            }
        }

        // Session active (login, switch back)
        observers.append(
            NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.sessionDidBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { _ in
                handleActive()
            }
        )

        // Session deactive (logout, fast user switch away)
        observers.append(
            NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.sessionDidResignActiveNotification,
                object: nil,
                queue: .main
            ) { _ in
                handleDeactive()
            }
        )

        // Screen locked → deactive
        observers.append(
            DistributedNotificationCenter.default().addObserver(
                forName: NSNotification.Name("com.apple.screenIsLocked"),
                object: nil,
                queue: .main
            ) { _ in
                handleDeactive()
            }
        )

        // Screen unlocked → active
        observers.append(
            DistributedNotificationCenter.default().addObserver(
                forName: NSNotification.Name("com.apple.screenIsUnlocked"),
                object: nil,
                queue: .main
            ) { _ in
                handleActive()
            }
        )
    }

    func stop() {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
            DistributedNotificationCenter.default().removeObserver(observer)
        }
        observers.removeAll()
    }
}
