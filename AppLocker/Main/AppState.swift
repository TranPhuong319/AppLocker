//
//  AppState.swift
//  AppLocker
//
//  Created by Doe Phương on 5/9/25.
//

import SwiftUI

/// Shared state & logic cho cả ContentView và TouchBar
class AppState: ObservableObject {
    static let shared = AppState()  // singleton
    @Published var manager = LockManager()
    @Published var showingAddApp = false
    @Published var showingDeleteQueue = false
    @Published var selectedToLock: Set<String> = []
    @Published var pendingLocks: Set<String> = []
    @Published var deleteQueue: Set<String> = []
    @Published var isLocking = false
    @Published var lastUnlockableApps: [InstalledApp] = []
    @Published var showingMenu = false
    @Published var isDisabled = false
    @Published var showingLockingPopup = false
    @Published var lockingMessage = ""
    @Published var searchTextUnlockaleApps = ""
    @Published var searchTextLockApps = ""
    
    var appsToUnlock: [String] {
        Array(deleteQueue)
    }
    
    @Published var activeTouchBar: TouchBarType = .mainWindow
    
    enum TouchBarType {
        case mainWindow
        case addAppPopup
        case deleteQueuePopup
    }
    
    var lockedAppObjects: [InstalledApp] {
        manager.lockedApps.keys.compactMap { path in
            let info = manager.lockedApps[path]!
            let icon = NSWorkspace.shared.icon(forFile: path) // icon theo path thật
            return InstalledApp(
                name: info.name,
                bundleID: "", // hoặc để bundleID trống nếu bạn chưa cần
                icon: icon,
                path: path
            )
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    
    var unlockableApps: [InstalledApp] {
        manager.allApps
            .filter { !manager.lockedApps.keys.contains($0.path) } // chưa bị khoá theo config
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    
    func toggleLockPopup(for apps: Set<String>, locking: Bool) {
        // đóng sheet chính
        if locking {
            showingAddApp = false
        } else {
            showingDeleteQueue = false
        }
        
        // hiện popup phụ với message phù hợp
        lockingMessage = locking
        ? "Locking %d apps...".localized(with: apps.count)
        : "Unlocking %d apps...".localized(with: apps.count)
        showingLockingPopup = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            self.manager.toggleLock(for: Array(apps))
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                if locking {
                    self.selectedToLock.removeAll()
                    self.pendingLocks.removeAll()
                } else {
                    self.deleteQueue.removeAll()
                }
                self.showingLockingPopup = false
            }
        }
    }
    
    // Logic từ nút +
    func openAddApp() {
        let currentApps = unlockableApps
        if currentApps != lastUnlockableApps {
            lastUnlockableApps = currentApps
        }
        showingAddApp = true
    }
    
    // Logic lock button trong popup khi nhấn nút +
    func lockButton() {
        toggleLockPopup(for: selectedToLock, locking: true)
    }
    
    // Close popup khi nhấn nút +
    func closeAddPopup() {
        showingAddApp = false
        selectedToLock.removeAll()
        pendingLocks.removeAll()
        searchTextLockApps = ""
    }
    
    // Nút thêm app khác trong popup khi nhấn +
    func addOthersApp() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.applicationBundle]
        
        if panel.runModal() == .OK, let url = panel.url {
            toggleLockPopup(for: [url.path], locking: true)
        }
    }
    
    // Unlock button trong waiting list
    func unlockApp() {
        toggleLockPopup(for: Set(appsToUnlock), locking: false)
    }
    
    // Nút xoá hết app trong hàng chờ khi unlock app
    func deleteAllFromWaitingList() {
        deleteQueue.removeAll()
        showingDeleteQueue = false
    }
}
