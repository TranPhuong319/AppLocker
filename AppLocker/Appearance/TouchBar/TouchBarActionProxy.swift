//
//  TouchBarActionProxy.swift
//  AppLocker
//
//  Created by Doe Phương on 5/9/25.
//

import AppKit

class TouchBarActionProxy: NSObject {
    static let shared = TouchBarActionProxy()

    @objc func openPopupAddApp() {
        AppState.shared.openAddApp()
    }

    @objc func lockApp() {
        AppState.shared.lockButton()
    }

    @objc func closeAddAppPopup() {
        AppState.shared.closeAddPopup()
    }

    @objc func addAnotherApp() {
        AppState.shared.addOthersApp(over: NSApp.keyWindow)
    }

    @objc func unlockApp() {
        AppState.shared.unlockApp()
    }

    @objc func clearWaitingList() {
        AppState.shared.deleteAllFromWaitingList()
    }

    @objc func showDeleteQueuePopup() {
        AppState.shared.showingDeleteQueue = true
    }
}
