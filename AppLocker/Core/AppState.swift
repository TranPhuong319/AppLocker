//
//  AppState.swift
//  AppLocker
//
//  Created by Doe Phương on 5/9/25.
//

import SwiftUI
import Combine

/// Shared state & logic cho cả ContentView và TouchBar
class AppState: ObservableObject {
    static let shared = AppState()  // singleton
    @Published var manager: any LockManagerProtocol
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
    @Published var searchTextLockApps = ""
    @Published var searchTextUnlockaleApps: String = ""
    
    @Published var filteredLockedApps: [InstalledApp] = []
    @Published var filteredUnlockableApps: [InstalledApp] = []
    
    // Backing published sources for computed lists so we can use Combine `$` publishers
    @Published private(set) var lockedAppObjects: [InstalledApp] = []
    @Published private(set) var unlockableApps: [InstalledApp] = []
    
    init() {
        if modeLock == "Launcher" {
            manager = LockLauncher()
        } else {
            manager = LockES()
        }
        setupSearchPipeline()
        refreshAppLists()
    }
    
    private func setupSearchPipeline() {
        // Kết hợp cả Text Search và Danh sách App gốc
        Publishers.CombineLatest($searchTextLockApps, $lockedAppObjects)
            .map { [weak self] (text, apps) -> [InstalledApp] in
                guard let self = self else { return [] }
                return self.performFilter(text: text, apps: apps)
            }
            .receive(on: DispatchQueue.main)
            .assign(to: &$filteredLockedApps)

        Publishers.CombineLatest($searchTextUnlockaleApps, $unlockableApps)
            .debounce(for: .milliseconds(200), scheduler: DispatchQueue.global()) // Giảm debounce cho mượt
            .map { [weak self] (text, apps) -> [InstalledApp] in
                guard let self = self else { return [] }
                return self.performFilter(text: text, apps: apps)
            }
            .receive(on: DispatchQueue.main)
            .assign(to: &$filteredUnlockableApps)
    }

    // Hàm hỗ trợ lọc dùng chung để code sạch hơn
    private func performFilter(text: String, apps: [InstalledApp]) -> [InstalledApp] {
        let query = text.lowercased().trimmingCharacters(in: .whitespaces)
        if query.isEmpty {
            return apps // Đã được sort sẵn trong computed property
        } else {
            return apps.filter { $0.name.lowercased().contains(query) }
        }
    }
    
    private func refreshAppLists() {
        // 1. Lấy danh sách Locked Apps
        let locked: [InstalledApp] = manager.lockedApps.keys.compactMap { path -> InstalledApp? in
            guard manager.lockedApps[path] != nil else { return nil }
            
            let icon = NSWorkspace.shared.icon(forFile: path)
            let name = FileManager.default.displayName(atPath: path)
                .replacingOccurrences(of: ".app", with: "", options: .caseInsensitive)
            
            // Xác định source dựa trên đường dẫn
            let source: AppSource = path.hasPrefix("/System") ? .system : .user
            
            return InstalledApp(name: name, bundleID: "", icon: icon, path: path, source: source)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        // 2. Lấy danh sách Unlockable Apps (Sửa lỗi tại đây)
        // Chèn kiểu [InstalledApp] rõ ràng cho biến allAppsFromManager
        let allAppsFromManager: [InstalledApp] = manager.allApps
        
        let unlockable: [InstalledApp] = allAppsFromManager
            .filter { (app: InstalledApp) -> Bool in
                // Chỉ định rõ (app: InstalledApp) giúp trình biên dịch không bị bối rối
                return !manager.lockedApps.keys.contains(app.path)
            }
            .map { app in
                // Gán source nếu app từ manager đang bị nil
                if app.source == nil {
                    let src: AppSource = app.path.hasPrefix("/System") ? .system : .user
                    return InstalledApp(name: app.name, bundleID: app.bundleID, icon: app.icon, path: app.path, source: src)
                }
                return app
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        // 3. Cập nhật UI trên Main Thread
        DispatchQueue.main.async {
            self.lockedAppObjects = locked
            self.unlockableApps = unlockable
        }
    }
    
    let setWidth = 450
    let setHeight = 450
    
    var appsToUnlock: [String] {
        Array(deleteQueue)
    }
    
    @Published var activeTouchBar: TouchBarType = .mainWindow
    
    enum TouchBarType {
        case mainWindow
        case addAppPopup
        case deleteQueuePopup
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
                
                self.manager.reloadAllApps()
                self.refreshAppLists()
                
                self.showingLockingPopup = false
            }
        }
    }
    
    // Logic từ nút +
    func openAddApp() {
        let currentApps = self.unlockableApps
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
