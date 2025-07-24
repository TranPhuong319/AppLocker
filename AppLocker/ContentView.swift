//
//  ContentView.swift
//  AppLocker
//
//  Created by Doe Phương on 24/07/2025.
//

import SwiftUI

struct InstalledApp: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let bundleID: String
    let icon: NSImage?
}

struct ContentView: View {
    @StateObject var manager = LockedAppsManager()

    var body: some View {
        VStack {
            Text("Danh sách ứng dụng đã cài")
                .font(.headline)
            List {
                ForEach(getInstalledApps(), id: \.self) { app in
                    Toggle(isOn: Binding<Bool>(
                        get: { manager.lockedApps.contains(app.bundleID) },
                        set: { _ in
                            DispatchQueue.main.async {
                                manager.toggleLock(for: app.bundleID)
                            }

                        }
                    )) {
                        HStack(alignment: .top, spacing: 10) {
                            if let icon = app.icon {
                                Image(nsImage: icon)
                                    .resizable()
                                    .frame(width: 32, height: 32)
                                    .cornerRadius(6)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(app.name)
                                    .font(.headline)
                                Text(app.bundleID)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .frame(height: 400)
        }
        .padding()
        .frame(width: 400)
    }

    func getInstalledApps() -> [InstalledApp] {
        let paths = ["/Applications"]
        var apps: [InstalledApp] = []

        for path in paths {
            let url = URL(fileURLWithPath: path)
            if let contents = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) {
                for appURL in contents where appURL.pathExtension == "app" {
                    if let bundle = Bundle(url: appURL),
                       let bundleID = bundle.bundleIdentifier {
                        let name = appURL.deletingPathExtension().lastPathComponent
                        let icon = NSWorkspace.shared.icon(forFile: appURL.path)
                        icon.size = NSSize(width: 32, height: 32)
                        apps.append(InstalledApp(name: name, bundleID: bundleID, icon: icon))
                    }
                }
            }
        }

        return apps
    }
}
