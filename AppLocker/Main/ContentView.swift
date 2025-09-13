//
//  ContentView.swift
//  AppLocker
//
//  Copyright © 2025 TranPhuong319. All rights reserved.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct InstalledApp: Identifiable, Hashable {
    let id: String
    let name: String
    let bundleID: String
    let icon: NSImage?
    let path: String

    init(name: String, bundleID: String, icon: NSImage?, path: String) {
        self.id = path
        self.name = name
        self.bundleID = bundleID
        self.icon = icon
        self.path = path
    }
}

struct ContentView: View {
    @ObservedObject var appState = AppState.shared
    @FocusState var isSearchFocused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 9) { // ✅ tất cả cách nhau 9
            // Label header
            HStack {
                Text("Locked application".localized)
                    .font(.headline)
                Spacer()
                Button {
                    appState.openAddApp()
                } label: {
                    Image(systemName: "plus")
                }
                .help("Add application to lock".localized)
                .disabled(appState.isDisabled)
            }
            
            if appState.lockedAppObjects.isEmpty {
                VStack {
                    Text("There is no locked application.".localized)
                        .foregroundColor(.secondary)
                        .font(.title3)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }
            } else {
                // Search field
                TextField("Search apps...".localized, text: $appState.searchTextLockApps)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding(.horizontal, 8)
                
                // ScrollView thay List
                ZStack(alignment: .bottom) {
                    ScrollView {
                        LazyVStack(alignment: .center, spacing: 6) {
                            ForEach(appState.lockedAppObjects.filter {
                                appState.searchTextLockApps.isEmpty || $0.name.localizedCaseInsensitiveContains(appState.searchTextLockApps)
                            }, id: \.id) { app in
                                HStack(spacing: 12) {
                                    if let icon = app.icon {
                                        Image(nsImage: icon)
                                            .resizable()
                                            .frame(width: 32, height: 32)
                                            .cornerRadius(6)
                                    }
                                    VStack(alignment: .leading) {
                                        Text(app.name)
                                    }
                                    Spacer()
                                    
                                    if appState.selectedToLock.contains(app.path) {
                                        Image(systemName: "checkmark.circle.fill")
                                    }
                                    Button {
                                        appState.deleteQueue.insert(app.path)
                                    } label: {
                                        Image(systemName: "minus.circle")
                                            .foregroundColor(.red)
                                    }
                                    .buttonStyle(BorderlessButtonStyle())
                                    .disabled(appState.deleteQueue.contains(app.path))
                                }
                                .padding(.vertical, 4)
                                .padding(.horizontal, 8)
                                .frame(maxWidth: 420)                       // width item
                                .background(
                                    RoundedRectangle(cornerRadius: 10)     // bo ngoài
                                        .fill(.ultraThinMaterial)            // blur
                                        .shadow(color: .black.opacity(0.2), radius: 3, x: 0, y: 2)
                                )
                                .frame(maxWidth: .infinity)                // căn giữa item trong ScrollView
                                .opacity(appState.deleteQueue.contains(app.path) ? 0.3 : 1.0)
                            }
                        }
                        .padding(.vertical, 4)
                        .frame(maxWidth: .infinity) // ScrollView vẫn full width
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .frame(maxHeight: .infinity) // ScrollView full height window

                    // Bottom bar nếu có deleteQueue
                    if !appState.deleteQueue.isEmpty {
                        Button {
                            appState.showingDeleteQueue = true
                        } label: {
                            HStack {
                                Image(systemName: "tray.full")
                                Text("Waiting for %d task(s)...".localized(with: appState.deleteQueue.count))
                                    .bold()
                            }
                            .frame(maxWidth: .infinity, maxHeight: 35)       // gộp frame
                            .padding(.horizontal)                         // padding ngoài
                            .background(Color.red.opacity(0.8))
                            .foregroundColor(.white)
                            .cornerRadius(8)
                            .shadow(radius: 4)
                        }
                        .buttonStyle(PlainButtonStyle())                 // giữ kiểu plain
                        .padding(.bottom, 8)                            // padding dưới
                        .transition(.move(edge: .bottom))               // animation hiện ẩn
                        .animation(.easeInOut, value: appState.deleteQueue.isEmpty)
                    }
                }
            }
        }
        .padding(12) // cách mép window
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $appState.showingAddApp) {
            NavigationStack {
                VStack(spacing: 0) {
                    // 🔍 Thanh search nằm ngay trên List
                    HStack {
                        TextField("Search apps...".localized, text: $appState.searchTextUnlockaleApps)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .padding(8)
                            .frame(maxWidth: .infinity) // ✅ full chiều ngang
                            .focused($isSearchFocused)
                    }

                    Divider()

                    // 📋 Danh sách app lọc theo search
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            let filteredApps = appState.unlockableApps.filter { app in
                                appState.searchTextUnlockaleApps.isEmpty ||
                                app.name.localizedCaseInsensitiveContains(appState.searchTextUnlockaleApps)
                            }
                            ForEach(filteredApps, id: \.id) { app in
                                HStack(spacing: 12) {
                                    if let icon = app.icon {
                                        Image(nsImage: icon)
                                            .resizable()
                                            .frame(width: 32, height: 32)
                                            .cornerRadius(6)
                                    }
                                    Text(app.name)
                                    Spacer()
                                    if appState.pendingLocks.contains(app.path) {
                                        Text("Locking...".localized)
                                            .italic()
                                            .foregroundColor(.gray)
                                    } else if appState.selectedToLock.contains(app.path) {
                                        Image(systemName: "checkmark.circle.fill")
                                    }
                                }
                                .padding(.vertical, 6)
                                .padding(.horizontal, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(.regularMaterial)      // blur
                                        .shadow(color: .black.opacity(0.06), radius: 5, x: 0, y: 2)  // chỉ tạo cảm giác nổi
                                )
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    guard !appState.pendingLocks.contains(app.path) else { return }
                                    if appState.selectedToLock.contains(app.path) {
                                        appState.selectedToLock.remove(app.path)
                                    } else {
                                        appState.selectedToLock.insert(app.path)
                                    }
                                }
                                .opacity(appState.selectedToLock.contains(app.path) ? 0.3 : 1.0)
                                .animation(.easeInOut(duration: 0.2), value: appState.selectedToLock)
                            }
                        }
                        .padding(.vertical, 8) // chỉ giữ padding dọc
                        .padding(.horizontal)  // 1 lớp padding ngoài
                    }
                    .frame(maxHeight: 520)

                }
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
            .onAppear {
                appState.manager.reloadAllApps()
                Logfile.core.info("List apps loaded")
                // Remove focus SwiftUI state
                isSearchFocused = false

                // Dispatch async để AppKit nhận sự thay đổi
                DispatchQueue.main.async {
                    NSApp.keyWindow?.makeFirstResponder(nil)
                }

            }
            .onDisappear {
                DispatchQueue.main.async {
                    appState.searchTextUnlockaleApps = ""
                }
            }
        }

        .sheet(isPresented: $appState.showingDeleteQueue) {
            VStack(alignment: .leading) {
                Text("Application is waiting to be deleted".localized)
                    .font(.headline)
                    .padding()

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        let filteredLockedApps = appState.lockedAppObjects.filter {
                            appState.searchTextLockApps.isEmpty || $0.name.localizedCaseInsensitiveContains(appState.searchTextLockApps)
                        }
                        ForEach(filteredLockedApps, id: \.id) { app in
                            HStack(spacing: 12) {
                                if let icon = app.icon {
                                    Image(nsImage: icon)
                                        .resizable()
                                        .frame(width: 32, height: 32)
                                        .cornerRadius(6)
                                }
                                Text(app.name)
                                Spacer()
                                Button {
                                    appState.deleteQueue.remove(app.path)
                                    if appState.deleteQueue.isEmpty {
                                        appState.showingDeleteQueue = false
                                    }
                                } label: {
                                    Image(systemName: "minus.circle")
                                        .foregroundColor(.red)
                                }
                                .buttonStyle(BorderlessButtonStyle())
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(.regularMaterial)      // blur
                                    .shadow(color: .black.opacity(0.2), radius: 5, x: 0, y: 2)  // chỉ tạo cảm giác nổi
                            )
                            .cornerRadius(10)
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
            .onDisappear {
                DispatchQueue.main.async {
                    appState.searchTextLockApps = ""
                }
            }

        }
        .sheet(isPresented: $appState.showingLockingPopup) {
            HStack(spacing: 12) {
                ProgressView()
                Text(appState.lockingMessage)
                    .font(.headline)
            }
            .padding()
            .frame(minWidth: 200, minHeight: 100)
        }
    }

    func toggleLockPopup(for apps: Set<String>, locking: Bool) {
        // đóng sheet chính
        if locking {
            appState.showingAddApp = false
        } else {
            appState.showingDeleteQueue = false
        }

        // hiện popup phụ với message phù hợp
        appState.lockingMessage = locking
            ? "Locking %d apps...".localized(with: apps.count)
            : "Unlocking %d apps...".localized(with: apps.count)
        appState.showingLockingPopup = true

        DispatchQueue.global(qos: .userInitiated).async {
            appState.manager.toggleLock(for: Array(apps))

            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                if locking {
                    appState.selectedToLock.removeAll()
                    appState.pendingLocks.removeAll()
                } else {
                    appState.deleteQueue.removeAll()
                }
                appState.showingLockingPopup = false
            }
        }
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

#Preview {
    PreviewWindow(content: ContentView())
}

