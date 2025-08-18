//
//  ContentView.swift
//  AppLocker
//
//  Copyright © 2025 TranPhuong319. All rights reserved.
//

import AppKit
import SwiftUI

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
    @StateObject private var manager = LockManager()
    @State private var showingAddApp = false
    @State private var showingDeleteQueue = false
    @State private var selectedToLock: Set<String> = []
    @State private var pendingLocks: Set<String> = []
    @State private var deleteQueue: Set<String> = []
    @State private var isLocking = false
    @State private var lastUnlockableApps: [InstalledApp] = []
    let launcherIcon = NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
    @State private var showingMenu = false
    @StateObject private var viewModel = ContentViewModel()
    @State private var isDisabled = false

    private var lockedAppObjects: [InstalledApp] {
        manager.allApps
            .filter { manager.lockedApps.keys.contains($0.path) }
            .map { app in
                if let info = manager.lockedApps[app.path] {
                    let appPath = "/Applications/\(info.name).app"
                    let icon = NSWorkspace.shared.icon(forFile: appPath) // load icon trực tiếp từ app bundle
                    return InstalledApp(
                        name: info.name,
                        bundleID: app.bundleID,
                        icon: icon,
                        path: app.path
                    )
                } else {
                    return app
                }
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }


    private var unlockableApps: [InstalledApp] {
        manager.allApps
            .filter { app in
                // Lọc: Không bị khoá & nằm trong đúng /Applications
                !manager.lockedApps.keys.contains(app.path)
                && app.path.hasPrefix("/Applications/")
                && !app.path.contains("/Contents/")
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text("Locked application".localized)
                    .font(.headline)
                Spacer()
                Button {
                    let currentApps = unlockableApps
                    if currentApps != lastUnlockableApps {
                        lastUnlockableApps = currentApps
                    }
                    showingAddApp = true
                } label: {
                    Image(systemName: "plus")
                }
                .help("Add application to lock".localized)
                .disabled(isDisabled)
            }
            .padding(.bottom, 4)

            if lockedAppObjects.isEmpty {
                Spacer()
                HStack {
                    Spacer()
                    Text("There is no locked application.".localized)
                        .foregroundColor(.secondary)
                        .font(.title3)
                        .padding()
                    Spacer()
                }
                Spacer()
            } else {
                ZStack(alignment: .bottom) {
                    List {
                        ForEach(lockedAppObjects, id: \.id) { app in
                            HStack(spacing: 12) {
                                if let icon = app.icon {
                                    Image(nsImage: icon)
                                        .resizable()
                                        .frame(width: 32, height: 32)
                                        .cornerRadius(6)
                                }
                                VStack(alignment: .leading) {
                                    Text(app.name)
//                                    Text(app.bundleID)
//                                        .font(.caption)
//                                        .foregroundColor(.secondary)
                                }
                                Spacer()

                                if selectedToLock.contains(app.path) {
                                    Image(systemName: "checkmark.circle.fill")
                                }
                                Button(action: {
                                    deleteQueue.insert(app.path)
                                }) {
                                    Image(systemName: "minus.circle")
                                        .foregroundColor(.red)
                                }
                                .buttonStyle(BorderlessButtonStyle())
                                .disabled(deleteQueue.contains(app.path))
                            }
                            .opacity(deleteQueue.contains(app.path) ? 0.5 : 1.0)
                            .contentShape(Rectangle())
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    deleteQueue.insert(app.path)
                                } label: {
                                    Label("Delete".localized, systemImage: "trash")
                                }
                            }
                        }
                        // Tạo khoảng trống padding để tránh nút đè lên text cuối list quá sát
                        Rectangle()
                            .frame(height: 60)
                            .opacity(0)
                            .listRowInsets(EdgeInsets()) // bỏ padding mặc định của row
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .listStyle(PlainListStyle()) // bỏ style mặc định cho list gọn hơn
                    if !deleteQueue.isEmpty {
                        Button {
                            showingDeleteQueue = true
                        } label: {
                            HStack {
                                Image(systemName: "tray.full")
                                Text("Waiting for %d task(s)...".localized(with: deleteQueue.count))
                                    .bold()
                            }
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.red.opacity(0.8))
                            .foregroundColor(.white)
                            .cornerRadius(8)
                            .padding(.horizontal)
                            .shadow(radius: 4)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .frame(height: 32) // chiều cao nút
                        .padding(.bottom, 8)
                        .transition(.move(edge: .bottom))
                        .animation(.easeInOut, value: deleteQueue.isEmpty)
                    }
                }
                .frame(height: 350)
            }
        }

        .padding(EdgeInsets(top: 15, leading: 15, bottom: 20, trailing: 15))
        .frame(maxWidth: 600, maxHeight: 400)
        .sheet(isPresented: $showingAddApp) {
            NavigationStack {
                    List {
                        ForEach(unlockableApps, id: \.id) { app in
                            HStack(spacing: 12) {
                                if let icon = app.icon {
                                    Image(nsImage: icon)
                                        .resizable()
                                        .frame(width: 32, height: 32)
                                        .cornerRadius(4)
                                }
                                Text(app.name)
                                Spacer()
                                if pendingLocks.contains(app.path) {
                                    Text("Locking...".localized)
                                        .italic()
                                        .foregroundColor(.gray)
                                } else if selectedToLock.contains(app.path) {
                                    Image(systemName: "checkmark.circle.fill")
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                guard !pendingLocks.contains(app.path) else { return }
                                if selectedToLock.contains(app.path) {
                                    selectedToLock.remove(app.path)
                                } else {
                                    selectedToLock.insert(app.path)
                                }
                            }
                            .opacity(selectedToLock.contains(app.path) ? 0.5 : 1.0)
                            .animation(.easeInOut(duration: 0.2), value: selectedToLock)
                        }
                    }
                    .navigationTitle("Select the application to lock".localized)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(action: lockSelected) {
                            if isLocking {
                                ProgressView()
                            } else {
                                Text("Lock (%d)".localized(with: selectedToLock.count))
                            }
                        }
                        
                        .accentColor(.accentColor)
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                        .disabled(selectedToLock.isEmpty || isLocking)
                    }
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close".localized) {
                            showingAddApp = false
                            selectedToLock.removeAll()
                            pendingLocks.removeAll()
                        }
                    }
                }
            }
            .frame(minWidth: 500, minHeight: 600)
        }
        .sheet(isPresented: $showingDeleteQueue) {
            VStack(alignment: .leading) {
                Text("Application is waiting to be deleted".localized)
                    .font(.headline)
                    .padding()

                List {
                    ForEach(lockedAppObjects.filter { deleteQueue.contains($0.path) }, id: \.id) { app in
                        HStack(spacing: 12) {
                            if let icon = app.icon {
                                Image(nsImage: icon)
                                    .resizable()
                                    .frame(width: 32, height: 32)
                                    .cornerRadius(4)
                            }
                            Text(app.name)
                            Spacer()
                            Button {
                                deleteQueue.remove(app.path)
                                // Đóng sheet nếu hàng chờ rỗng
                                if deleteQueue.isEmpty {
                                    showingDeleteQueue = false
                                }
                            } label: {
                                Image(systemName: "minus.circle")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(BorderlessButtonStyle())
                        }
                    }
                }

                Divider()

                HStack {
                    Spacer()
                    Button("Delete all from the waiting list".localized) {
                        deleteQueue.removeAll()
                        showingDeleteQueue = false
                    }
                    .keyboardShortcut(.cancelAction)
                    let appsToUnlock = Array(deleteQueue)
                    Button("Unlock".localized) {
                        DispatchQueue.main.async {
                            manager.toggleLock(for: appsToUnlock)
                            Logfile.core.info("🧾 deleteQueue: \(appsToUnlock, privacy: .public)")
                            deleteQueue.removeAll()
                            showingDeleteQueue = false
                        }
                    }
                    .accentColor(.accentColor)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            }
            .frame(minWidth: 500, minHeight: 400)
        }
    }

    private func lockSelected() {
        isLocking = true
        pendingLocks = selectedToLock
        DispatchQueue.global(qos: .userInitiated).async {
            manager.toggleLock(for: Array(pendingLocks))
            DispatchQueue.main.async {
                isLocking = false
                showingAddApp = false
                selectedToLock.removeAll()
                pendingLocks.removeAll()
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

            if manager.lockedApps.keys.contains(subApp.path) {
                return true
            }
        }

        return false
    }
}

class ContentViewModel: ObservableObject {
    var settingsWC: SettingsWindowController?

    func openSettingsWindow() {
        if settingsWC == nil {
            settingsWC = SettingsWindowController()
            settingsWC?.window?.identifier = NSUserInterfaceItemIdentifier("SettingsWindow")
        }
        settingsWC?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}


#Preview {
    ContentView()
}
