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
    @StateObject private var manager = LockManager()
    @State private var showingAddApp = false
    @State private var showingDeleteQueue = false
    @State private var selectedToLock: Set<String> = []
    @State private var pendingLocks: Set<String> = []
    @State private var deleteQueue: Set<String> = []
    @State private var isLocking = false
    @State private var lastUnlockableApps: [InstalledApp] = []
    @State private var showingMenu = false
    @State private var isDisabled = false
    @State private var showingLockingPopup = false
    @State private var lockingMessage = ""
    @State private var searchTextUnlockaleApps = ""
    @State private var searchTextLockApps = ""

    private var lockedAppObjects: [InstalledApp] {
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

    private var unlockableApps: [InstalledApp] {
        manager.allApps
            .filter { !manager.lockedApps.keys.contains($0.path) } // chưa bị khoá theo config
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) { // ✅ tất cả cách nhau 9
            // Label header
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
                // Search field
                TextField("Search apps...".localized, text: $searchTextLockApps)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding(.horizontal, 8)

                // ScrollView thay List
                ZStack(alignment: .bottom) {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 6) {
                            ForEach(lockedAppObjects.filter {
                                searchTextLockApps.isEmpty || $0.name.localizedCaseInsensitiveContains(searchTextLockApps)
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

                                    if selectedToLock.contains(app.path) {
                                        Image(systemName: "checkmark.circle.fill")
                                    }
                                    Button {
                                        deleteQueue.insert(app.path)
                                    } label: {
                                        Image(systemName: "minus.circle")
                                            .foregroundColor(.red)
                                    }
                                    .buttonStyle(BorderlessButtonStyle())
                                    .disabled(deleteQueue.contains(app.path))
                                }
                                .padding(.vertical, 4)
                                .padding(.horizontal, 8)
                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                                .opacity(deleteQueue.contains(app.path) ? 0.3 : 1.0)
                            }

                            Spacer(minLength: 60) // tránh bar dưới đè app cuối
                        }
                        .padding(.vertical, 4)
                    }
                    .frame(height: 350)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    // 🔴 Bottom bar nếu có deleteQueue
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
                            .frame(maxWidth: .infinity, maxHeight: 40)
                            .background(Color.red.opacity(0.8))
                            .foregroundColor(.white)
                            .cornerRadius(8)
                            .padding(.horizontal)
                            .shadow(radius: 4)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .frame(height: 32)
                        .padding(.bottom, 8)
                        .transition(.move(edge: .bottom))
                        .animation(.easeInOut, value: deleteQueue.isEmpty)
                    }
                }
            }
        }       
        .padding(12) // ✅ cách mép window 8pt
        .sheet(isPresented: $showingAddApp) {
            NavigationStack {
                VStack(spacing: 0) {
                    // 🔍 Thanh search nằm ngay trên List
                    HStack {
                        TextField("Search apps...".localized, text: $searchTextUnlockaleApps)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .padding(8)
                            .frame(maxWidth: .infinity) // ✅ full chiều ngang

                    }

                    Divider()

                    // 📋 Danh sách app lọc theo search
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(unlockableApps.filter {
                                searchTextUnlockaleApps.isEmpty ||
                                $0.name.localizedCaseInsensitiveContains(searchTextUnlockaleApps)
                            }, id: \.id) { app in
                                HStack(spacing: 12) {
                                    if let icon = app.icon {
                                        Image(nsImage: icon)
                                            .resizable()
                                            .frame(width: 32, height: 32)
                                            .cornerRadius(6)
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
                                .padding(.vertical, 6)
                                .padding(.horizontal, 10)
                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    guard !pendingLocks.contains(app.path) else { return }
                                    if selectedToLock.contains(app.path) {
                                        selectedToLock.remove(app.path)
                                    } else {
                                        selectedToLock.insert(app.path)
                                    }
                                }
                                .opacity(selectedToLock.contains(app.path) ? 0.3 : 1.0)
                                .animation(.easeInOut(duration: 0.2), value: selectedToLock)
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
                            toggleLockPopup(for: selectedToLock, locking: true)
                        }) {
                            Text("Lock (%d)".localized(with: selectedToLock.count))
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

                    ToolbarItem(placement: .automatic) {
                        Button("Others…") {
                            let panel = NSOpenPanel()
                            panel.allowsMultipleSelection = true
                            panel.canChooseFiles = true
                            panel.canChooseDirectories = false
                            panel.allowedContentTypes = [.applicationBundle]

                            if panel.runModal() == .OK, let url = panel.url {
                                toggleLockPopup(for: [url.path], locking: true)
                            }
                        }
                    }
                }
            }
            .frame(minWidth: 500, minHeight: 600)
            .onAppear {
                manager.reloadAllApps()
                Logfile.core.info("List apps loaded")
            }
        }

        .sheet(isPresented: $showingDeleteQueue) {
            VStack(alignment: .leading) {
                Text("Application is waiting to be deleted".localized)
                    .font(.headline)
                    .padding()

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(lockedAppObjects.filter { deleteQueue.contains($0.path) }, id: \.id) { app in
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
                                    deleteQueue.remove(app.path)
                                    if deleteQueue.isEmpty {
                                        showingDeleteQueue = false
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
                            .background(.regularMaterial)
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
                        deleteQueue.removeAll()
                        showingDeleteQueue = false
                    }
                    .keyboardShortcut(.cancelAction)
                    let appsToUnlock = Array(deleteQueue)
                    Button("Unlock".localized) {
                        toggleLockPopup(for: Set(appsToUnlock), locking: false)
                    }
                    .accentColor(.accentColor)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            }
            .frame(minWidth: 400, minHeight: 450)
        }
        .sheet(isPresented: $showingLockingPopup) {
            HStack(spacing: 12) {
                ProgressView()
                Text(lockingMessage)
                    .font(.headline)
            }
            .padding()
            .frame(minWidth: 200, minHeight: 100)
        }
    }

    private func toggleLockPopup(for apps: Set<String>, locking: Bool) {
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
            manager.toggleLock(for: Array(apps))

            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                if locking {
                    selectedToLock.removeAll()
                    pendingLocks.removeAll()
                } else {
                    deleteQueue.removeAll()
                }
                showingLockingPopup = false
            }
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

#Preview {
    ContentView()
}
