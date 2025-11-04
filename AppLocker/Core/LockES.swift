//
//  LockES.swift
//  AppLocker
//
//  Created by Doe Phương on 27/9/25.
//

import AppKit
import Foundation
import CryptoKit

class LockES: LockManagerProtocol {
    @Published var lockedApps: [String: LockedAppConfig] = [:] // keyed by path
    @Published var allApps: [InstalledApp] = []
    private var periodicTimer: Timer?

    init() {
        ExtensionInstaller.shared.onInstalled = {
            self.lockedApps = ConfigStore.shared.load()
            self.allApps = self.getInstalledApps()
            self.startPeriodicRescan() // 🧠 Thêm dòng này
        }
    }

    // MARK: - Installed apps discovery (unchanged)
    func getInstalledApps() -> [InstalledApp] {
        let appsDirs = ["/Applications", "/System/Applications"]
        var allApps: [InstalledApp] = []
        let fileManager = FileManager.default
        
        for dir in appsDirs {
            let dirURL = URL(fileURLWithPath: dir)
            guard let contents = try? fileManager.contentsOfDirectory(at: dirURL, includingPropertiesForKeys: nil) else {
                continue
            }
            
            let apps = contents.compactMap { url -> InstalledApp? in
                guard url.pathExtension == "app",
                      let bundle = Bundle(url: url),
                      let bundleID = bundle.bundleIdentifier else {
                    return nil
                }
                
                let name = url.deletingPathExtension().lastPathComponent
                let icon = NSWorkspace.shared.icon(forFile: url.path)
                icon.size = NSSize(width: 32, height: 32)
                
                return InstalledApp(name: name, bundleID: bundleID, icon: icon, path: url.path)
            }
            
            allApps.append(contentsOf: apps)
        }
        
        return allApps
    }

    // MARK: - Persistence helper
    func save() {
        ConfigStore.shared.save(self.lockedApps)
    }

    // MARK: - SHA helper
    private func computeSHA(for executablePath: String) -> String {
        let url = URL(fileURLWithPath: executablePath)
        guard let data = try? Data(contentsOf: url) else { return "" }
        let h = SHA256.hash(data: data)
        return h.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Toggle lock (ES mode: chỉ ghi config và publish)
    func toggleLock(for paths: [String]) {
        var didChange = false

        for path in paths {
            if let _ = lockedApps[path] {
                // đang bị block -> remove
                lockedApps.removeValue(forKey: path)
                didChange = true
            } else {
                guard let bundle = Bundle(url: URL(fileURLWithPath: path)),
                      let execName = bundle.object(forInfoDictionaryKey: "CFBundleExecutable") as? String
                else {
                    NSLog("❌ Cannot read Info.plist for \(path)")
                    continue
                }

                let appName = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
                let execPath = "\(path)/Contents/MacOS/\(execName)"
                let sha = computeSHA(for: execPath)
                let bundleID = bundle.bundleIdentifier ?? ""

                let mode = modeLock ?? "ES"
                let cfg = LockedAppConfig(
                    bundleID: bundleID,
                    path: path,
                    sha256: sha,
                    blockMode: mode,
                    execFile: execName,
                    name: appName
                )
                lockedApps[path] = cfg
                didChange = true
            }
        }

        if didChange {
            save()
            publishToExtension()
        }
    }

    // MARK: - Send config to ES Extension
    func publishToExtension() {
        let arr = lockedApps.values.map { $0.toDict() }
        DispatchQueue.global().async {
            ESXPCClient.shared.updateBlockedApps(arr)
        }
    }

    func reloadAllApps() {
        DispatchQueue.global(qos: .background).async {
            let apps = self.getInstalledApps()
            DispatchQueue.main.async {
                self.allApps = apps
            }
        }
    }

    func isLocked(path: String) -> Bool {
        return lockedApps[path] != nil
    }
}

// MARK: - Auto SHA Rescan (định kỳ)
extension LockES {
    func startPeriodicRescan(interval: TimeInterval = 300) {
        // chỉ chạy 1 timer duy nhất
        if periodicTimer != nil { return }
        
        periodicTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            self.rescanLockedApps()
        }
        RunLoop.current.add(periodicTimer!, forMode: .common)
        NSLog("⏱️ Bắt đầu quét SHA định kỳ mỗi \(Int(interval)) giây")
    }

    func stopPeriodicRescan() {
        periodicTimer?.invalidate()
        periodicTimer = nil
    }

    @objc func rescanLockedApps() {
        NSLog("🔍 Đang quét lại SHA các app đã khóa...")
        var changed = false
        var updatedMap = lockedApps

        for (path, cfg) in lockedApps {
            let exeFile = cfg.execFile ?? "Unknown"
            let execPath = "\(path)/Contents/MacOS/\(exeFile)"
            guard FileManager.default.fileExists(atPath: execPath) else { continue }
            
            let newSHA = computeSHA(for: execPath)
            if newSHA.isEmpty { continue }

            if newSHA != cfg.sha256 {
                let name = cfg.name ?? "Unknown"
                let oldHash = cfg.sha256
                NSLog("⚠️ SHA thay đổi cho \(name): \(oldHash.prefix(8)) → \(newSHA.prefix(8))")
                let updatedCfg = LockedAppConfig(
                    bundleID: cfg.bundleID,
                    path: cfg.path,
                    sha256: newSHA,
                    blockMode: cfg.blockMode,
                    execFile: cfg.execFile,
                    name: cfg.name
                )
                updatedMap[path] = updatedCfg
                changed = true
            }
        }

        if changed {
            lockedApps = updatedMap
            save()
            publishToExtension()
            NSLog("✅ Đã cập nhật SHA mới & gửi lại ES")
        } else {
            NSLog("✅ Không có thay đổi SHA nào")
        }
    }
}
