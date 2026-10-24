//
//  AppState+Actions.swift
//  AppLocker
//
//  Created by Doe Phương on 9/10/26.
//

import AppKit
import Foundation

extension AppState {
    func toggleLockPopup(for apps: Set<String>, locking: Bool) {
        if locking {
            showingAddApp = false
        } else {
            showingDeleteQueue = false
        }

        lockingMessage =
            locking
            ? String(localized: "Locking \(apps.count) apps...")
            : String(localized: "Unlocking \(apps.count) apps...")
        showingLockingPopup = true

        let appsArray = Array(apps)

        Task { [weak self] in
            // Cho SwiftUI 1 nhịp (0.15s) để hiển thị mượt mà sheet LockingPopupSheet
            try? await Task.sleep(for: .milliseconds(150))
            guard let self else { return }

            self.manager.toggleLock(for: appsArray)

            if locking {
                self.selectedToLock.removeAll()
            } else {
                self.deleteQueue.removeAll()
            }

            self.refreshAppLists()

            self.showingLockingPopup = false
        }
    }

    @objc func openAddApp() {
        showingAddApp = true
    }

    @objc func lockSelectedApps() {
        toggleLockPopup(for: selectedToLock, locking: true)
    }

    @objc func dismissAddAppSheet() {
        showingAddApp = false
        selectedToLock.removeAll()
        searchTextLockApps = ""
    }

    @objc func chooseCustomApp() {
        addOtherApps(over: NSApp.keyWindow)
    }

    @objc func unlockQueuedApps() {
        toggleLockPopup(for: deleteQueue, locking: false)
    }

    @objc func clearDeleteQueue() {
        deleteQueue.removeAll()
        showingDeleteQueue = false
    }

    @objc func showDeleteQueueSheet() {
        showingDeleteQueue = true
    }
}
