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
        // gọi trực tiếp logic nút + từ AppState
        AppState.shared.openAddApp()
    }

    @objc func lockApp() {
        // gọi trực tiếp logic nút Lock từ AppState
        AppState.shared.lockButton()
    }
    
    @objc func closeAddAppPopup() {
        // gọi trực tiếp logic nút Lock từ AppState
        AppState.shared.closeAddPopup()
    }
    
    @objc func addAnotherApp() {
        // gọi trực tiếp logic nút Lock từ AppState
        AppState.shared.addOthersApp()
    }
    
    @objc func unlockApp() {
        // gọi trực tiếp logic nút Lock từ AppState
        AppState.shared.unlockApp()
    }
    
    @objc func clearWaitingList() {
        // gọi trực tiếp logic nút Lock từ AppState
        AppState.shared.deleteAllFromWaitingList()
    }
}
