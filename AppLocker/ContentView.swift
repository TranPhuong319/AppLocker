//
//  ContentView.swift
//  AppLocker
//
//  Created by Doe Phương on 24/07/2025.
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
        id = bundleID
        self.name = name
        self.bundleID = bundleID
        self.icon = icon
        self.path = path
    }
}

struct ContentView: View {
    @StateObject private var manager = LockedAppsManager()
    @State private var showingAddApp = false
    @State private var showingDeleteQueue = false
    @State private var selectedToLock: Set<String> = []
    @State private var pendingLocks: Set<String> = []
    @State private var deleteQueue: Set<String> = []
    @State private var isLocking = false

    private var allApps: [InstalledApp] { getInstalledApps() }

    private var lockedAppObjects: [InstalledApp] {
        allApps
            .filter { manager.lockedApps.contains($0.bundleID) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var unlockableApps: [InstalledApp] {
        allApps
            .filter {
                !manager.lockedApps.contains($0.bundleID) &&
                    !FileManager.default.fileExists(atPath: $0.path + ".real")
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text("Ứng dụng đã khoá")
                    .font(.headline)
                Spacer()
                Button { showingAddApp = true } label: {
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
                            Button(action: {
                                deleteQueue.insert(app.bundleID)
                            }) {
                                Image(systemName: "minus.circle")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(BorderlessButtonStyle())
                            .disabled(deleteQueue.contains(app.bundleID)) // không thêm lại nếu đã có
                        }
                        .opacity(deleteQueue.contains(app.bundleID) ? 0.5 : 1.0)
                        .contentShape(Rectangle())
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                deleteQueue.insert(app.bundleID)
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
                            if pendingLocks.contains(app.bundleID) {
                                Text("Đang khoá...")
                                    .italic()
                                    .foregroundColor(.gray)
                            } else if selectedToLock.contains(app.bundleID) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.accentColor)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            guard !pendingLocks.contains(app.bundleID) else { return }
                            if selectedToLock.contains(app.bundleID) {
                                selectedToLock.remove(app.bundleID)
                            } else {
                                selectedToLock.insert(app.bundleID)
                            }
                        }
                        .opacity(selectedToLock.contains(app.bundleID) ? 0.5 : 1.0)
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
                    ForEach(lockedAppObjects.filter { deleteQueue.contains($0.bundleID) }, id: \.id) { app in
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
                                deleteQueue.remove(app.bundleID)
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

                    Button("Mở khoá") {
                        manager.toggleLock(for: Array(deleteQueue))
                        deleteQueue.removeAll()
                        showingDeleteQueue = false
                    }
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

    private func getInstalledApps() -> [InstalledApp] {
        let paths = ["/Applications"]
        var apps: [InstalledApp] = []
        for path in paths {
            let url = URL(fileURLWithPath: path)
            guard let contents = try? FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: nil
            ) else { continue }
            for appURL in contents where appURL.pathExtension == "app" {
                if let bundle = Bundle(url: appURL), let bundleID = bundle.bundleIdentifier {
                    let name = appURL.deletingPathExtension().lastPathComponent
                    let icon = NSWorkspace.shared.icon(forFile: appURL.path)
                    icon.size = NSSize(width: 32, height: 32)
                    apps.append(
                        InstalledApp(
                            name: name,
                            bundleID: bundleID,
                            icon: icon,
                            path: appURL.path
                        )
                    )
                }
            }
        }
        return apps
    }
}


////
//
////  MARK: ContentView.swift
//
////  AppLocker
////
////  Created by Doe Phương on 24/07/2025.
////
//
//import AppKit
//import SwiftUI
//
//struct InstalledApp: Identifiable, Hashable {
//    let id: String
//    let name: String
//    let bundleID: String
//    let icon: NSImage?
//    let path: String
//
//    init(name: String, bundleID: String, icon: NSImage?, path: String) {
//        id = bundleID
//        self.name = name
//        self.bundleID = bundleID
//        self.icon = icon
//        self.path = path
//    }
//}
//
//struct ContentView: View {
//    @StateObject private var manager = LockManager()
//    @State private var showingAddApp = false
//    @State private var showingDeleteQueue = false
//    @State private var selectedToLock: Set<String> = []
//    @State private var pendingLocks: Set<String> = []
//    @State private var deleteQueue: Set<String> = []
//    @State private var isLocking = false
//    @StateObject private var lockManager = LockManager()
//    @FocusState private var isUnlockButtonFocused: Bool
//
//    private var allApps: [InstalledApp] { getInstalledApps() }
//
//    private var lockedAppObjects: [InstalledApp] {
//        allApps
//            .filter { manager.lockedApps.contains($0.bundleID) }
//            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
//    }
//
//    private var unlockableApps: [InstalledApp] {
//        allApps
//            .filter {
//                !manager.lockedApps.contains($0.bundleID) &&
//                    !FileManager.default.fileExists(atPath: $0.path + ".real")
//            }
//            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
//    }
//
//    var body: some View {
//        VStack(alignment: .leading) {
//            HStack {
//                Text("Ứng dụng đã khoá")
//                    .font(.headline)
//                Spacer()
//                Button { showingAddApp = true } label: {
//                    Image(systemName: "plus")
//                }
//                .help("Thêm ứng dụng để khoá")
//            }
//            .padding(.bottom, 4)
//
//            if lockedAppObjects.isEmpty {
//                Spacer()
//                HStack {
//                    Spacer()
//                    Text("Không có ứng dụng nào bị khoá.")
//                        .foregroundColor(.secondary)
//                        .font(.title3)
//                        .padding()
//                    Spacer()
//                }
//                Spacer()
//            } else {
//                List {
//                    ForEach(lockedAppObjects, id: \.id) { app in
//                        HStack(spacing: 12) {
//                            if let icon = app.icon {
//                                Image(nsImage: icon)
//                                    .resizable()
//                                    .frame(width: 32, height: 32)
//                                    .cornerRadius(6)
//                            }
//                            VStack(alignment: .leading) {
//                                Text(app.name)
//                                Text(app.bundleID)
//                                    .font(.caption)
//                                    .foregroundColor(.secondary)
//                            }
//                            Spacer()
//                            Button(action: {
//                                deleteQueue.insert(app.bundleID)
//                            }) {
//                                Image(systemName: "minus.circle")
//                                    .foregroundColor(.red)
//                            }
//                            .buttonStyle(BorderlessButtonStyle())
//                            .disabled(deleteQueue.contains(app.bundleID))
//                        }
//                        .opacity(deleteQueue.contains(app.bundleID) ? 0.5 : 1.0)
//                        .contentShape(Rectangle())
//                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
//                            Button(role: .destructive) {
//                                deleteQueue.insert(app.bundleID)
//                            } label: {
//                                Label("Xoá", systemImage: "trash")
//                            }
//                        }
//                    }
//
//                    if !deleteQueue.isEmpty {
//                        Spacer()
//
//                        Button {
//                            showingDeleteQueue = true
//                        } label: {
//                            HStack {
//                                Image(systemName: "tray.full")
//                                Text("Đang chờ \(deleteQueue.count) tác vụ...")
//                                    .bold()
//                            }
//                            .padding()
//                            .frame(maxWidth: .infinity)
//                            .background(Color.red)
//                            .foregroundColor(.white)
//                            .cornerRadius(8)
//                            .padding(.horizontal)
//                        }
//                        .buttonStyle(PlainButtonStyle())
//                        .padding(.bottom, 10)
//                    }
//                }
//                .frame(maxWidth: .infinity, maxHeight: .infinity)
//            }
//        }
//        .padding()
//        .frame(maxWidth: 600, maxHeight: 400)
//        .sheet(isPresented: $showingAddApp) {
//            NavigationStack {
//                List {
//                    ForEach(unlockableApps, id: \.id) { app in
//                        HStack(spacing: 12) {
//                            if let icon = app.icon {
//                                Image(nsImage: icon)
//                                    .resizable()
//                                    .frame(width: 24, height: 24)
//                                    .cornerRadius(4)
//                            }
//                            Text(app.name)
//                            Spacer()
//                            if pendingLocks.contains(app.bundleID) {
//                                Text("Đang khoá...")
//                                    .italic()
//                                    .foregroundColor(.gray)
//                            } else if selectedToLock.contains(app.bundleID) {
//                                Image(systemName: "checkmark.circle.fill")
//                                    .foregroundColor(.accentColor)
//                            }
//                        }
//                        .contentShape(Rectangle())
//                        .onTapGesture {
//                            guard !pendingLocks.contains(app.bundleID) else { return }
//                            if selectedToLock.contains(app.bundleID) {
//                                selectedToLock.remove(app.bundleID)
//                            } else {
//                                selectedToLock.insert(app.bundleID)
//                            }
//                        }
//                        .opacity(selectedToLock.contains(app.bundleID) ? 0.5 : 1.0)
//                        .animation(.easeInOut(duration: 0.2), value: selectedToLock)
//                    }
//                }
//                .navigationTitle("Chọn ứng dụng để khoá")
//                .toolbar {
//                    ToolbarItem(placement: .confirmationAction) {
//                        Button(action: lockSelected) {
//                            if isLocking {
//                                ProgressView()
//                            } else {
//                                Text("Khoá (\(selectedToLock.count))")
//                            }
//                        }
//                        .focused($isUnlockButtonFocused)
//                        .onAppear {
//                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
//                                isUnlockButtonFocused = true
//                            }
//                        }
////                        .buttonStyle(.borderedProminent)
//                        .disabled(selectedToLock.isEmpty || isLocking)
//                    }
//                    ToolbarItem(placement: .cancellationAction) {
//                        Button("Đóng") {
//                            showingAddApp = false
//                            selectedToLock.removeAll()
//                            pendingLocks.removeAll()
//                        }
//                    }
//                }
//            }
//            .frame(minWidth: 500, minHeight: 600)
//        }
//        .sheet(isPresented: $showingDeleteQueue) {
//            VStack(alignment: .leading) {
//                Text("Ứng dụng đang chờ xoá")
//                    .font(.headline)
//                    .padding()
//
//                List {
//                    ForEach(lockedAppObjects.filter { deleteQueue.contains($0.bundleID) }, id: \.id) { app in
//                        HStack(spacing: 12) {
//                            if let icon = app.icon {
//                                Image(nsImage: icon)
//                                    .resizable()
//                                    .frame(width: 24, height: 24)
//                                    .cornerRadius(4)
//                            }
//                            Text(app.name)
//                            Spacer()
//                            Button {
//                                deleteQueue.remove(app.bundleID)
//                                if deleteQueue.isEmpty {
//                                    showingDeleteQueue = false
//                                }
//                            } label: {
//                                Image(systemName: "minus.circle")
//                                    .foregroundColor(.red)
//                            }
//                            .buttonStyle(BorderlessButtonStyle())
//                        }
//                    }
//                }
//
//                Divider()
//
//                HStack {
//                    Spacer()
//                    Button("Xoá tất cả khỏi hàng chờ") {
//                        deleteQueue.removeAll()
//                        showingDeleteQueue = false
//                    }
//                    .keyboardShortcut(.cancelAction)
//
//                    Button("Mở khoá") {
//                        for bundleID in deleteQueue {
//                            lockManager.toggleLock(for: bundleID)
//                        }
//                        lockManager.applyPendingChanges(for: app.bundleID)
//                        deleteQueue.removeAll()
//                        showingDeleteQueue = false
//                        
//                    }
//                    .focused($isUnlockButtonFocused)
//                    .onAppear {
//                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
//                            isUnlockButtonFocused = true
//                        }
//                    }
//                    .keyboardShortcut(.defaultAction)
//                }
//                .padding()
//            }
//            .frame(minWidth: 500, minHeight: 400)
//        }
//    }
//
//    private func lockSelected() {
//        DispatchQueue.main.async {
//            self.isLocking = true
//            self.pendingLocks = self.selectedToLock
//        }
//
//        DispatchQueue.main.async {
//            for bundleID in selectedToLock {
//                lockManager.toggleLock(for: bundleID)
//            }
//            lockManager.applyPendingChanges(for: app.bundleID)
//
//            DispatchQueue.main.async {
//                self.isLocking = false
//                self.showingAddApp = false
//                self.selectedToLock.removeAll()
//                self.pendingLocks.removeAll()
//            }
//        }
//    }
//
//    func getInstalledApps() -> [InstalledApp] {
//        let paths = ["/Applications"]
//        var apps: [InstalledApp] = []
//
//        for path in paths {
//            let url = URL(fileURLWithPath: path)
//            if let contents = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) {
//                for appURL in contents where appURL.pathExtension == "app" {
//                    if let bundle = Bundle(url: appURL),
//                       let bundleID = bundle.bundleIdentifier {
//                        let name = appURL.deletingPathExtension().lastPathComponent
//                        let icon = NSWorkspace.shared.icon(forFile: appURL.path)
//                        icon.size = NSSize(width: 32, height: 32)
//                        apps.append(InstalledApp(name: name, bundleID: bundleID, icon: icon, path: appURL.path))
//                    }
//                }
//            }
//        }
//
//        return apps
//    }
//}
