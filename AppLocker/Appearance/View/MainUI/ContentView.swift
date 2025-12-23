//
//  ContentView.swift
//  AppLocker
//
//  Copyright © 2025 TranPhuong319. All rights reserved.
//
//  EN: Main UI for managing locked applications.
//  VI: Giao diện chính để quản lý các ứng dụng bị khóa.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

// EN: Source of installed application (user/system).
// VI: Nguồn của ứng dụng đã cài (người dùng/hệ thống).
enum AppSource: String {
    case user = "Applications"
    case system = "System"
}

// EN: Lightweight model for an installed app shown in the UI.
// VI: Mô hình nhẹ cho ứng dụng đã cài hiển thị trên giao diện.
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
        .contentShape(Rectangle())
        .onTapGesture { isSearchFocused = false }
        // EN: Split sheets into dedicated builders to keep main body lean.
        // VI: Tách các sheet thành các hàm riêng để phần body chính gọn nhẹ.
        .sheet(isPresented: $appState.showingAddApp) { addAppSheet }
        .sheet(isPresented: $appState.showingDeleteQueue) { deleteQueueSheet }
        .sheet(isPresented: $appState.showingLockingPopup) { lockingPopupSheet }
    }
    
    // MARK: - Subviews / Thành phần con
    @ViewBuilder
    private var headerView: some View {
        HStack {
            Text("Locked application".localized).font(.headline)
            Spacer()
            Button { appState.openAddApp() } label: { Image(systemName: "plus") }
            .help("Add application to lock".localized)
            .disabled(appState.isDisabled)
        }
        .padding(.horizontal, 8)
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
            // EN: 1) Search bar — unified padding with container.
            // VI: 1) Thanh tìm kiếm — đồng nhất padding với container.
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .padding(.leading, 4) // EN: Nudge icon inward. VI: Đẩy biểu tượng vào nhẹ.
                
                TextField("Search apps...".localized, text: $appState.searchTextLockApps)
                    .textFieldStyle(.plain) // EN: Remove default field border. VI: Bỏ khung mặc định của TextField.
                    .focused($isSearchFocused)
                    .onSubmit { unfocus() }
            }
            .padding(7) // EN: Spacing between content and bar frame. VI: Tạo khoảng trống giữa nội dung và khung.
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.2))
            )
            .padding(.horizontal, 8)
            
            ZStack(alignment: .bottom) {
                ScrollView {
                    LazyVStack(alignment: .center, spacing: 6) {
                        let apps = appState.filteredLockedApps
                        let userApps = apps.filter { $0.source == .user }
                        let systemApps = apps.filter { $0.source == .system }
                        
                        if !userApps.isEmpty {
                            SectionHeader(title: "Applications".localized)
                            ForEach(userApps, id: \.path) { lockedAppRow(for: $0) }
                        }
                        
                        if !systemApps.isEmpty {
                            SectionHeader(title: "System Applications".localized)
                            ForEach(systemApps, id: \.path) { lockedAppRow(for: $0) }
                        }
                        
                        // EN: If both groups are empty but there are apps (e.g., missing source), list all.
                        // VI: Nếu cả hai nhóm trống nhưng vẫn có app (ví dụ thiếu nguồn), hiển thị tất cả.
                        if userApps.isEmpty && systemApps.isEmpty && !apps.isEmpty {
                            ForEach(apps) { lockedAppRow(for: $0) }
                        }
                    }
                    .padding(.vertical, 4)
                    .padding(.bottom, appState.deleteQueue.isEmpty ? 0 : 60)
                }
                .scrollIndicators(.hidden)
                .background(Color.white.opacity(0.000001).onTapGesture { isSearchFocused = false })
                .clipShape(RoundedRectangle(cornerRadius: 12))
                
                if !appState.deleteQueue.isEmpty {
                    deleteQueueNotificationBar
                }
            }
            .animation(.spring(), value: appState.deleteQueue.isEmpty)
        }
    }
    
    // MARK: - Row Helper / Trợ giúp hàng
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
    
    // MARK: - Sheets / Hộp thoại
    @ViewBuilder
    private var addAppSheet: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // EN: 1) Search bar — dedicated to add-app sheet.
                // VI: 1) Thanh tìm kiếm — dành riêng cho popup thêm app.
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                        .padding(.leading, 4) // EN: Nudge icon inward. VI: Đẩy biểu tượng vào nhẹ.
                    
                    TextField("Search apps...".localized, text: $appState.searchTextUnlockaleApps)
                        .textFieldStyle(.plain) // EN: Remove default field border. VI: Bỏ khung mặc định của TextField.
                        .focused($isSearchFocused)
                        .onSubmit { unfocus() }
                }
                .padding(7) // EN: Spacing between content and bar frame. VI: Tạo khoảng trống giữa nội dung và khung.
                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.2))
                )
                .padding(.horizontal)
                .padding(.vertical)
                Divider()
                
                // EN: 2) App list grouped by source.
                // VI: 2) Danh sách ứng dụng theo nhóm nguồn.
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
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
                    }
                    .padding(.vertical, 8)
                }
                .scrollIndicators(.hidden)
                .padding(.horizontal) // EN: Align list indent with search bar. VI: Canh lề danh sách bằng thanh tìm kiếm.
                .frame(maxWidth: .infinity)
                .frame(maxHeight: 420)
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
        .frame(minWidth: 400, minHeight: 500)
        .onTapGesture { unfocus() }
        .onAppear {
            unfocus() // EN: Ensure not focused on launch. VI: Đảm bảo khi mở không bị focus.
            appState.manager.reloadAllApps()
                        
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                // EN: Force AppKit to release any active first responder from text fields.
                // VI: Ép AppKit nhả First Responder của mọi TextField đang hoạt động.
                NSApp.keyWindow?.makeFirstResponder(nil)
                
                // EN: Touch Bar configuration for this sheet.
                // VI: Cấu hình Touch Bar cho sheet này.
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
    // EN: Helper to fully clear focus from fields.
    // VI: Hàm bổ trợ để hệ thống nhả focus hoàn toàn.
    private func unfocus() {
        isSearchFocused = false
        // EN: Ask current window to resign first responder (AppKit interop).
        // VI: Yêu cầu Window hiện tại nhả First Responder (tương tác AppKit).
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
        VStack(alignment: .leading, spacing: 0) {
            Text("Application is waiting to be deleted".localized)
                .font(.headline)
                .padding([.horizontal, .top]) // EN: Keep only top & horizontal padding. VI: Chỉ giữ padding trên và hai bên.
                .padding(.bottom, 0)
            
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    // EN: Filter apps that are in the delete queue.
                    // VI: Lọc các ứng dụng nằm trong hàng đợi xóa.
                    let appsInQueue = appState.lockedAppObjects.filter { appState.deleteQueue.contains($0.path) }
                    
                    // EN: Group 1 — User apps.
                    // VI: Nhóm 1 — Ứng dụng người dùng.
                    let userApps = appsInQueue.filter { $0.source == .user }
                    if !userApps.isEmpty {
                        SectionHeader(title: "Applications".localized)
                        ForEach(userApps, id: \.path) { app in
                            deleteQueueRow(for: app)
                        }
                    }
                    
                    // EN: Group 2 — System apps.
                    // VI: Nhóm 2 — Ứng dụng hệ thống.
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
            .scrollIndicators(.hidden)
            .frame(maxHeight: 270)
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
        .frame(minWidth: 350, minHeight: 370)
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
    
    // EN: Separate row builder for delete queue for clarity.
    // VI: Tạo hàm Row riêng cho Delete Queue để code gọn gàng.
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
        
    // MARK: - Helper / Trợ giúp
    @ViewBuilder
    func SectionHeader(title: String) -> some View {
        HStack(spacing: 10) { // EN: Gap between text and separator. VI: Khoảng cách giữa chữ và thanh ngang.
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundColor(.secondary.opacity(0.8))
                .layoutPriority(1) // EN: Avoid truncation for long text. VI: Tránh bị cắt khi chữ dài.
            
            Rectangle()
                .fill(Color.secondary.opacity(0.2))
                .frame(height: 1)
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 2)
        .padding(.top, 6)
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
                    .foregroundColor(.primary) // EN: Keep text color independent from Button. VI: Giữ màu chữ không phụ thuộc Button.
                
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
            .frame(maxWidth: .infinity) // EN: Make row fill full width. VI: Ép hàng chiếm toàn bộ chiều ngang.
            .contentShape(Rectangle())  // EN: Entire area (incl. Spacer) is tappable. VI: Toàn bộ vùng (kể cả Spacer) có thể nhấn.
            .opacity(appState.selectedToLock.contains(app.path) ? 0.5 : 1.0) // EN: Dim when selected. VI: Làm mờ khi đã chọn.
        }
        .buttonStyle(AppRowButtonStyle()) // EN: Apply press feedback. VI: Áp dụng hiệu ứng nhấn.
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

struct AppRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                // EN: Rounded background when pressed.
                // VI: Nền bo góc khi nhấn.
                RoundedRectangle(cornerRadius: 12)
                    .fill(configuration.isPressed ? Color.gray.opacity(0.15) : Color.clear)
                    .padding(.horizontal, 4) // EN: Keep some gap from edges. VI: Tạo khoảng cách với mép.
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
            .contentShape(Rectangle()) // EN: Preserve full-row hit testing. VI: Giữ khả năng bấm toàn dòng.
    }
}

#Preview {
    ContentView()
        .frame(width: CGFloat(AppState.shared.setWidth),
               height: CGFloat(AppState.shared.setHeight))
}

