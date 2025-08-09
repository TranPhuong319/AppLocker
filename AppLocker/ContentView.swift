//
//  ContentView.swift
//  AppLocker
//
//  Created by Doe Phương on 24/07/2025.
//

import AppKit
import SwiftUI

struct InstalledApp: Identifiable, Hashable {
    let id: String         // <-- path, không còn là bundleID
    let name: String
    let bundleID: String
    let icon: NSImage?
    let path: String

    init(name: String, bundleID: String, icon: NSImage?, path: String) {
        self.id = path     // ✅ dùng path tuyệt đối
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
    
//
//    private var allApps: [InstalledApp] { getInstalledApps() }

    private var lockedAppObjects: [InstalledApp] {
        manager.allApps
            .filter { manager.lockedApps.keys.contains($0.path) }
            .map { app in
                if let info = manager.lockedApps[app.path] {
                    let iconPath = "/Applications/\(info.name).app/Contents/Resources/AppIcon.icns"
                    let icon = NSImage(contentsOfFile: iconPath)
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
                Text("Ứng dụng đã khoá")
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
                .help("Thêm ứng dụng để khoá")
            }
            .padding(.bottom, 4)

            if lockedAppObjects.isEmpty {
                Spacer()
                HStack {
                    Spacer()
                    Text("Không có ứng dụng nào bị khoá.")
                        .foregroundColor(.secondary)
                        .font(.title3)
                        .padding()
                    Spacer()
                }
                Spacer()
            } else {
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
                                Text(app.bundleID)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()

                            // ✅ Dấu tick nếu đã chọn
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
                            .disabled(deleteQueue.contains(app.path)) // không thêm lại nếu đã có
                        }
                        .opacity(deleteQueue.contains(app.path) ? 0.5 : 1.0)
                        .contentShape(Rectangle())
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                deleteQueue.insert(app.path)
                            } label: {
                                Label("Xoá", systemImage: "trash")
                            }
                        }
                    }

                    if !deleteQueue.isEmpty {
                        Spacer() // đẩy toàn bộ list app lên

                        Button {
                            showingDeleteQueue = true
                        } label: {
                            HStack {
                                Image(systemName: "tray.full")
                                Text("Đang chờ \(deleteQueue.count) tác vụ...")
                                    .bold()
                            }
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.red)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                            .padding(.horizontal)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .padding(.bottom, 10)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding()
        .frame(maxWidth: 600, maxHeight: 400)
        .sheet(isPresented: $showingAddApp) {
            NavigationStack {
                List {
                    ForEach(unlockableApps, id: \.id) { app in
                        HStack(spacing: 12) {
                            if let icon = app.icon {
                                Image(nsImage: icon)
                                    .resizable()
                                    .frame(width: 24, height: 24)
                                    .cornerRadius(4)
                            }
                            Text(app.name)
                            Spacer()
                            if pendingLocks.contains(app.path) {
                                Text("Đang khoá...")
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
                .navigationTitle("Chọn ứng dụng để khoá")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(action: lockSelected) {
                            if isLocking {
                                ProgressView()
                            } else {
                                Text("Khoá (\(selectedToLock.count))")
                            }
                        }
                        .accentColor(.accentColor)
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                        .disabled(selectedToLock.isEmpty || isLocking)
                    }
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Đóng") {
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
                Text("Ứng dụng đang chờ xoá")
                    .font(.headline)
                    .padding()

                List {
                    ForEach(lockedAppObjects.filter { deleteQueue.contains($0.path) }, id: \.id) { app in
                        HStack(spacing: 12) {
                            if let icon = app.icon {
                                Image(nsImage: icon)
                                    .resizable()
                                    .frame(width: 24, height: 24)
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
                    Button("Xoá tất cả khỏi hàng chờ") {
                        deleteQueue.removeAll()
                        showingDeleteQueue = false
                    }
                    .keyboardShortcut(.cancelAction)
                    let appsToUnlock = Array(deleteQueue)
                    Button("Mở khoá") {
                        DispatchQueue.main.async {
                            manager.toggleLock(for: appsToUnlock)
                            print("🧾 deleteQueue:", appsToUnlock)
                            deleteQueue.removeAll()
                            showingDeleteQueue = false
                        }
                    }
                    .accentColor(.accentColor)
                    .keyboardShortcut(.defaultAction)
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
                let bundleID = infoDict["CFBundleIdentifier"] as? String
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
