//
//  ContentView.swift
//  AppLocker
//
//  Copyright © 2025 TranPhuong319. All rights reserved.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum AppSource: String {
    case user = "Applications"
    case system = "System"
}

struct InstalledApp: Identifiable, Hashable {
    let id: String
    let name: String
    let bundleID: String
    let icon: NSImage?
    let path: String
    let source: AppSource?

    init(name: String, bundleID: String, icon: NSImage?, path: String, source: AppSource? = nil) {
        self.id = path
        self.name = name
        self.bundleID = bundleID
        self.icon = icon
        self.path = path
        self.source = source
    }
}

struct ContentView: View {
    @ObservedObject var appState = AppState.shared
    @FocusState var isSearchFocused: Bool
    @EnvironmentObject var appstate: AppState
    
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            headerView
            
            if appState.lockedAppObjects.isEmpty {
                emptyStateView
            } else {
                mainListView
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { isSearchFocused = false }
        // Tách các sheet ra các hàm riêng để giảm tải cho body chính
        .sheet(isPresented: $appState.showingAddApp) { addAppSheet }
        .sheet(isPresented: $appState.showingDeleteQueue) { deleteQueueSheet }
        .sheet(isPresented: $appState.showingLockingPopup) { lockingPopupSheet }
    }
    
    // MARK: - Subviews
    @ViewBuilder
    private var headerView: some View {
        HStack {
            Text("Locked application".localized).font(.headline)
            Spacer()
            Button { appState.openAddApp() } label: { Image(systemName: "plus") }
            .help("Add application to lock".localized)
            .disabled(appState.isDisabled)
        }
    }
    
    @ViewBuilder
    private var emptyStateView: some View {
        Text("There is no locked application.".localized)
            .foregroundColor(.secondary)
            .font(.title3)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
    
    @ViewBuilder
    private var mainListView: some View {
        VStack(spacing: 9) {
            TextField("Search apps...".localized, text: $appState.searchTextLockApps)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding(.horizontal, 8)
                .focused($isSearchFocused)
                .onSubmit { isSearchFocused = false }
            
            ZStack(alignment: .bottom) {
                ScrollView {
                    LazyVStack(alignment: .center, spacing: 6) {
                        let apps = appState.filteredLockedApps
                        let userApps = apps.filter { $0.source == .user }
                        let systemApps = apps.filter { $0.source == .system }
                        let unknownApps = apps.filter { $0.source == nil } // Phòng hờ source bị nil

                        if !userApps.isEmpty {
                            SectionHeader(title: "Applications".localized)
                            ForEach(userApps) { lockedAppRow(for: $0) }
                        }

                        if !systemApps.isEmpty {
                            SectionHeader(title: "System Applications".localized)
                            ForEach(systemApps) { lockedAppRow(for: $0) }
                        }

                        // Nếu cả 2 group trên đều trống nhưng apps lại có dữ liệu (do source bị nil)
                        if userApps.isEmpty && systemApps.isEmpty && !apps.isEmpty {
                            ForEach(apps) { lockedAppRow(for: $0) }
                        }
                    }
                    .padding(.vertical, 4)
                    .padding(.bottom, appState.deleteQueue.isEmpty ? 0 : 60)
                }
                .background(Color.white.opacity(0.000001).onTapGesture { isSearchFocused = false })
                .clipShape(RoundedRectangle(cornerRadius: 12))
                
                if !appState.deleteQueue.isEmpty {
                    deleteQueueNotificationBar
                }
            }
            .animation(.spring(), value: appState.deleteQueue.isEmpty)
        }
    }
    
    // MARK: - Row Helper
    @ViewBuilder
    private func lockedAppRow(for app: InstalledApp) -> some View {
        HStack(spacing: 12) {
            if let icon = app.icon {
                Image(nsImage: icon).resizable().frame(width: 32, height: 32).cornerRadius(6)
            }
            Text(app.name)
            Spacer()
            if appState.selectedToLock.contains(app.path) {
                Image(systemName: "checkmark.circle.fill")
            }
            Button {
                withAnimation(.spring()) {
                    _ = appState.deleteQueue.insert(app.path)
                }
            } label: {
                Image(systemName: "minus.circle").foregroundColor(.red)
            }
            .buttonStyle(BorderlessButtonStyle())
            .disabled(appState.deleteQueue.contains(app.path))
        }
        .padding(.vertical, 4).padding(.horizontal, 8)
        .frame(maxWidth: 420).frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { isSearchFocused = false }
        .opacity(appState.deleteQueue.contains(app.path) ? 0.3 : 1.0)
    }
    
    // MARK: - Sheets
    @ViewBuilder
    private var addAppSheet: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Thanh search nằm ngay trên List
                HStack {
                    TextField("Search apps...".localized, text: $appState.searchTextUnlockaleApps)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .padding(8)
                        .frame(maxWidth: .infinity) // full chiều ngang
                        .focused($isSearchFocused)
                        .onSubmit { unfocus() } // Hàm phụ để ép nhả focus
                }
                
                Divider()
                
                // Danh sách app lọc theo search
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        if modeLock == "ES" {
                            let userApps = appState.filteredUnlockableApps.filter { $0.source == .user }
                            if !userApps.isEmpty {
                                SectionHeader(title: "Applications".localized)
                                ForEach(userApps, id: \.path) { app in
                                    appRow(for: app)
                                }
                            }
                            
                            let systemApps = appState.filteredUnlockableApps.filter { $0.source == .system }
                            if !systemApps.isEmpty {
                                SectionHeader(title: "System Applications".localized)
                                    .padding(.top, 10)
                                ForEach(systemApps, id: \.path) { app in
                                    appRow(for: app)
                                }
                            }
                            
                        } else {
                            ForEach(appState.filteredUnlockableApps) { app in
                                appRow(for: app)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal)
                }
                .frame(maxHeight: 520)
            }
            .contentShape(Rectangle())
            .onTapGesture { unfocus() }
            .navigationTitle("Select the application to lock".localized)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: {
                        appState.lockButton()
                    }) {
                        Text("Lock (%d)".localized(with: appState.selectedToLock.count))
                    }
                    .accentColor(.accentColor)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(appState.selectedToLock.isEmpty || appState.isLocking)
                }

                ToolbarItem(placement: .cancellationAction) {
                    Button("Close".localized) {
                        appState.closeAddPopup()
                    }
                }

                ToolbarItem(placement: .automatic) {
                    Button("Others…") {
                        appState.addOthersApp()
                    }
                }
            }
        }
        .frame(minWidth: 500, minHeight: 600)
        .onTapGesture { unfocus() }
        .onAppear {
            unfocus() // Đảm bảo lúc mở lên không tự focus vào TextField
            appState.manager.reloadAllApps()
                        
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                // Ép AppKit nhả focus của mọi TextField đang hoạt động
                NSApp.keyWindow?.makeFirstResponder(nil)
                
                // TouchBar logic
                let tb = TouchBarManager.shared.makeTouchBar(for: .addAppPopup)
                NSApp.keyWindow?.touchBar = tb
            }
        }
            
        .onDisappear {
            DispatchQueue.main.async {
                appState.searchTextUnlockaleApps = ""
                if let mainWindow = NSApp.windows.first(where: { $0.isVisible && !$0.isSheet }) {
                    TouchBarManager.shared.apply(to: mainWindow, type: .mainWindow)
                }
            }
        }
    }
    // Hàm bổ trợ để ép hệ thống nhả Focus hoàn toàn
    private func unfocus() {
        isSearchFocused = false
        // Can thiệp AppKit: Bắt Window hiện tại nhả First Responder
        DispatchQueue.main.async {
            NSApp.keyWindow?.makeFirstResponder(nil)
        }
    }
    
    @ViewBuilder
    private var deleteQueueNotificationBar: some View {
        Button { appState.showingDeleteQueue = true } label: {
            HStack {
                Image(systemName: "tray.full")
                Text("Waiting to unlock %d application(s)...".localized(with: appState.deleteQueue.count)).bold()
            }
            .frame(maxWidth: .infinity, maxHeight: 35)
            .background(Color.red.opacity(0.8)).foregroundColor(.white).cornerRadius(8).shadow(radius: 4)
        }
        .buttonStyle(PlainButtonStyle()).padding(.horizontal, 16).padding(.bottom, 12)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
    
    @ViewBuilder
    private var deleteQueueSheet: some View {
        VStack(alignment: .leading) {
            Text("Application is waiting to be deleted".localized)
                .font(.headline)
                .padding()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    // Lọc danh sách app nằm trong Queue
                    let appsInQueue = appState.lockedAppObjects.filter { appState.deleteQueue.contains($0.path) }
                    
                    // Nhóm 1: User Apps
                    let userApps = appsInQueue.filter { $0.source == .user }
                    if !userApps.isEmpty {
                        SectionHeader(title: "Applications".localized)
                        ForEach(userApps, id: \.path) { app in
                            deleteQueueRow(for: app)
                        }
                    }
                    
                    // Nhóm 2: System Apps
                    let systemApps = appsInQueue.filter { $0.source == .system }
                    if !systemApps.isEmpty {
                        SectionHeader(title: "System Applications".localized)
                        ForEach(systemApps, id: \.path) { app in
                            deleteQueueRow(for: app)
                        }
                    }
                }
                .padding(.vertical, 8)
            }
            .frame(maxHeight: 350)
            .padding(.horizontal)

            Divider()

            HStack {
                Spacer()
                Button("Delete all from the waiting list".localized) {
                    appState.deleteAllFromWaitingList()
                }
                .keyboardShortcut(.cancelAction)
                Button("Unlock".localized) {
                    appState.unlockApp()
                }
                .accentColor(.accentColor)
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(minWidth: 400, minHeight: 450)
        .onAppear {
            DispatchQueue.main.async {
                let tb = TouchBarManager.shared.makeTouchBar(for: .deleteQueuePopup)
                NSApp.keyWindow?.touchBar = tb
            }
        }
        .onDisappear {
            DispatchQueue.main.async {
                if let mainWindow = NSApp.windows.first(where: { $0.isVisible && !$0.isSheet }) {
                    TouchBarManager.shared.apply(to: mainWindow, type: .mainWindow)
                }
                appState.searchTextLockApps = ""
            }
        }
    }
    
    // Tạo thêm hàm Row riêng cho Delete Queue để code gọn hơn
    @ViewBuilder
    private func deleteQueueRow(for app: InstalledApp) -> some View {
        HStack(spacing: 12) {
            if let icon = app.icon {
                Image(nsImage: icon).resizable().frame(width: 32, height: 32).cornerRadius(6)
            }
            Text(app.name)
            Spacer()
            Button {
                withAnimation {
                    appState.deleteQueue.remove(app.path)
                    if appState.deleteQueue.isEmpty { appState.showingDeleteQueue = false }
                }
            } label: {
                Image(systemName: "minus.circle").foregroundColor(.red)
            }
            .buttonStyle(BorderlessButtonStyle())
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
    }
    
    @ViewBuilder
    private var lockingPopupSheet: some View {
        HStack(spacing: 12) {
            ProgressView()
            Text(appState.lockingMessage)
                .font(.headline)
        }
        .padding()
        .frame(minWidth: 200, minHeight: 100)
    }
        
    // MARK: - Helper
    @ViewBuilder
    func SectionHeader(title: String) -> some View {
        HStack(spacing: 10) { // Khoảng cách giữa chữ và thanh ngang
            Text(title) // Chữ in hoa nhẹ nhìn sẽ chuyên nghiệp hơn
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundColor(.secondary.opacity(0.8))
                .layoutPriority(1) // Đảm bảo chữ không bị cắt nếu quá dài
            
            // Thanh ngang nối tiếp chữ
            Rectangle()
                .fill(Color.secondary.opacity(0.2))
                .frame(height: 1) // Độ dày thanh ngang
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 4)
        .padding(.top, 12)
    }
    
    @ViewBuilder
    func appRow(for app: InstalledApp) -> some View {
        Button {
            unfocus()
            guard !appState.pendingLocks.contains(app.path) else { return }
            
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                if appState.selectedToLock.contains(app.path) {
                    appState.selectedToLock.remove(app.path)
                } else {
                    appState.selectedToLock.insert(app.path)
                }
            }
        } label: {
            HStack(spacing: 12) {
                if let icon = app.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 32, height: 32)
                        .cornerRadius(6)
                } else {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 32, height: 32)
                }
                
                Text(app.name)
                    .font(.body)
                    .foregroundColor(.primary) // Đảm bảo text không bị đổi màu theo Button
                
                Spacer()
                
                if appState.pendingLocks.contains(app.path) {
                    Text("Locking...".localized)
                        .italic()
                        .foregroundColor(.secondary)
                        .font(.subheadline)
                } else if appState.selectedToLock.contains(app.path) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.accentColor)
                        .font(.title3)
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity) // Ép HStack chiếm hết chiều ngang của List
            .contentShape(Rectangle())  // Biến toàn bộ diện tích (kể cả vùng Spacer) thành vùng nhấn
            // Hiệu ứng mờ cố định khi đã được chọn vào danh sách chờ lock
            .opacity(appState.selectedToLock.contains(app.path) ? 0.5 : 1.0)
        }
        .buttonStyle(AppRowButtonStyle()) // Áp dụng hiệu ứng nhấn
    }
    
    func isAppStubbedAsLocked(_ appURL: URL) -> Bool {
        let resourceDir = appURL.appendingPathComponent("Contents/Resources")

        guard let subApps = try? FileManager.default.contentsOfDirectory(at: resourceDir, includingPropertiesForKeys: nil) else {
            return false
        }

        for subApp in subApps where subApp.pathExtension == "app" {
            let infoPlist = subApp.appendingPathComponent("Contents/Info.plist")
            guard
                let infoDict = NSDictionary(contentsOf: infoPlist) as? [String: Any],
                let _ = infoDict["CFBundleIdentifier"] as? String
            else {
                continue
            }

            if appState.manager.lockedApps.keys.contains(subApp.path) {
                return true
            }
        }

        return false
    }
}

struct PreviewWindow<Content: View>: View {
    @ObservedObject var appState = AppState.shared
    let content: Content
    var body: some View {
        content
            .frame(width: CGFloat(appState.setWidth), height: CGFloat(appState.setHeight))
    }
}

struct AppRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                // Sử dụng RoundedRectangle để bo cong nền khi nhấn
                RoundedRectangle(cornerRadius: 12)
                    .fill(configuration.isPressed ? Color.gray.opacity(0.15) : Color.clear)
                    .padding(.horizontal, 4) // Thêm chút padding để nền không chạm sát mép
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
            .contentShape(Rectangle()) // Vẫn giữ cái này để nhận diện click toàn dòng
    }
}

#Preview {
    PreviewWindow(content: ContentView())
}

