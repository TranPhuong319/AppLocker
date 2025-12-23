//
//  AppState.swift
//  AppLocker
//
//  Created by Doe Phương on 5/9/25.
//
//  EN: Shared observable state and UI coordination for ContentView and Touch Bar.
//  VI: Trạng thái quan sát dùng chung và điều phối UI cho ContentView và Touch Bar.
//

import SwiftUI
import Combine

// EN: Shared state & logic for ContentView and Touch Bar.
// VI: Trạng thái & logic dùng chung cho ContentView và Touch Bar.
class AppState: ObservableObject {
    static let shared = AppState()  // EN: Singleton instance. VI: Thực thể singleton.
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
    
    // EN: Backing published sources for computed lists to leverage Combine `$`.
    // VI: Nguồn Published nền cho danh sách tính toán để tận dụng Combine `$`.
    @Published private(set) var lockedAppObjects: [InstalledApp] = []
    @Published private(set) var unlockableApps: [InstalledApp] = []
    
    init() {
        switch modeLock {
        case .launcher:
            manager = LockLauncher()
        case .es:
            manager = LockES()
        case .none:
            // VI: Xử lý trường hợp modeLock chưa được set (mặc định hoặc báo lỗi)
            Logfile.core.error("No mode selected during AppState init, defaulting to Launcher")
            manager = LockLauncher()
        }
        
        setupSearchPipeline()
        refreshAppLists()
    }
    
    private func setupSearchPipeline() {
        // EN: Combine text search with the source lists for responsive filtering.
        // VI: Kết hợp tìm kiếm văn bản với danh sách nguồn để lọc mượt mà.
        Publishers.CombineLatest($searchTextLockApps, $lockedAppObjects)
            .map { [weak self] (text, apps) -> [InstalledApp] in
                guard let self = self else { return [] }
                return self.performFilter(text: text, apps: apps)
            }
            .receive(on: DispatchQueue.main)
            .assign(to: &$filteredLockedApps)

        Publishers.CombineLatest($searchTextUnlockaleApps, $unlockableApps)
            .debounce(for: .milliseconds(200), scheduler: DispatchQueue.global()) // EN: Small debounce for smooth typing. VI: Giảm debounce để gõ mượt.
            .map { [weak self] (text, apps) -> [InstalledApp] in
                guard let self = self else { return [] }
                return self.performFilter(text: text, apps: apps)
            }
            .receive(on: DispatchQueue.main)
            .assign(to: &$filteredUnlockableApps)
    }

    // EN: Common filtering helper to keep code DRY.
    // VI: Hàm lọc dùng chung để code gọn gàng.
    private func performFilter(text: String, apps: [InstalledApp]) -> [InstalledApp] {
        let query = text.lowercased().trimmingCharacters(in: .whitespaces)
        if query.isEmpty {
            return apps // EN: Already sorted upstream. VI: Đã được sắp xếp từ trước.
        } else {
            return apps.filter { $0.name.lowercased().contains(query) }
        }
    }
    
    private func refreshAppLists() {
        // EN: 1) Build the list of locked apps from the manager.
        // VI: 1) Tạo danh sách ứng dụng đã khóa từ manager.
        let locked: [InstalledApp] = manager.lockedApps.keys.compactMap { path -> InstalledApp? in
            guard manager.lockedApps[path] != nil else { return nil }
            
            let icon = NSWorkspace.shared.icon(forFile: path)
            let name = FileManager.default.displayName(atPath: path)
                .replacingOccurrences(of: ".app", with: "", options: .caseInsensitive)
            
            // EN: Determine source by path prefix.
            // VI: Xác định nguồn dựa trên tiền tố đường dẫn.
            let source: AppSource = path.hasPrefix("/System") ? .system : .user
            
            return InstalledApp(name: name, bundleID: "", icon: icon, path: path, source: source)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        // EN: 2) Build the list of unlockable apps.
        // VI: 2) Tạo danh sách ứng dụng có thể khóa.
        let allAppsFromManager: [InstalledApp] = manager.allApps // EN: Explicit type helps inference. VI: Khai báo kiểu rõ ràng để tránh lỗi suy luận.
        
        let unlockable: [InstalledApp] = allAppsFromManager
            .filter { (app: InstalledApp) -> Bool in
                // EN: Exclude those already locked.
                // VI: Loại các ứng dụng đã bị khóa.
                return !manager.lockedApps.keys.contains(app.path)
            }
            .map { app in
                // EN: Fill missing source if needed based on path.
                // VI: Bổ sung nguồn nếu thiếu dựa trên đường dẫn.
                if app.source == nil {
                    let src: AppSource = app.path.hasPrefix("/System") ? .system : .user
                    return InstalledApp(name: app.name, bundleID: app.bundleID, icon: app.icon, path: app.path, source: src)
                }
                return app
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        // EN: 3) Update UI-bound lists on the main thread.
        // VI: 3) Cập nhật danh sách gắn với UI trên Main Thread.
        DispatchQueue.main.async {
            self.lockedAppObjects = locked
            self.unlockableApps = unlockable
        }
    }
    
    let setWidth = 450 // Chiều ngang
    let setHeight = 470 // chiều cao
    
    var appsToUnlock: [String] {
        Array(deleteQueue)
    }
    
    @Published var activeTouchBar: TouchBarType = .mainWindow
    
    enum TouchBarType {
        case mainWindow
        case addAppPopup
        case deleteQueuePopup
    }
    
    // EN: Toggle the lock/unlock popup and perform the operation.
    // VI: Bật tắt popup khóa/mở khóa và thực thi thao tác.
    func toggleLockPopup(for apps: Set<String>, locking: Bool) {
        // EN: Close the appropriate sheet.
        // VI: Đóng sheet phù hợp.
        if locking {
            showingAddApp = false
        } else {
            showingDeleteQueue = false
        }
        
        // EN: Show secondary popup with contextual message.
        // VI: Hiển thị popup phụ với thông điệp phù hợp.
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
    
    // EN: Logic from the "+" button to open add-app sheet.
    // VI: Logic từ nút "+" để mở popup thêm ứng dụng.
    func openAddApp() {
        let currentApps = self.unlockableApps
        if currentApps != lastUnlockableApps {
            lastUnlockableApps = currentApps
        }
        showingAddApp = true
    }
    
    // EN: Lock button in the add-app popup.
    // VI: Nút khóa trong popup thêm ứng dụng.
    func lockButton() {
        toggleLockPopup(for: selectedToLock, locking: true)
    }
    
    // EN: Close the add-app popup and reset selections.
    // VI: Đóng popup thêm ứng dụng và đặt lại lựa chọn.
    func closeAddPopup() {
        showingAddApp = false
        selectedToLock.removeAll()
        pendingLocks.removeAll()
        searchTextLockApps = ""
    }
    
    // EN: Add other apps via open panel.
    // VI: Thêm ứng dụng khác thông qua hộp thoại mở file.
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
    
    // EN: Unlock button in the waiting list sheet.
    // VI: Nút mở khóa trong sheet hàng đợi.
    func unlockApp() {
        toggleLockPopup(for: Set(appsToUnlock), locking: false)
    }
    
    // EN: Remove all apps from the waiting list.
    // VI: Xóa tất cả ứng dụng khỏi danh sách chờ.
    func deleteAllFromWaitingList() {
        deleteQueue.removeAll()
        showingDeleteQueue = false
    }
}
