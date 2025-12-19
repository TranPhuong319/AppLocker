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
        self.lockedApps = ConfigStore.shared.load()
        self.allApps = self.getInstalledApps()
        Logfile.core.info("Start scanning SHA...")
        self.rescanLockedApps()
        self.startPeriodicRescan()
    }

    // MARK: - Installed apps discovery (unchanged)
    func getInstalledApps() -> [InstalledApp] {
        let appsDirs = ["/Applications", "/System/Applications"]
        var allApps: [InstalledApp] = []
        let fileManager = FileManager.default
        
        for dir in appsDirs {
            let dirURL = URL(fileURLWithPath: dir)
            
            // 🧭 Duyệt toàn bộ cây thư mục con, bỏ qua file ẩn
            guard let enumerator = fileManager.enumerator(
                at: dirURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles, .skipsPackageDescendants] // tránh lồng sâu trong .app khác
            ) else { continue }
            
            for case let fileURL as URL in enumerator {
                // 🎯 Chỉ lấy app bundle
                guard fileURL.pathExtension == "app",
                      !fileURL.lastPathComponent.hasPrefix("."),
                      let bundle = Bundle(url: fileURL),
                      let bundleID = bundle.bundleIdentifier else {
                    continue
                }
                
                // Dùng tên hiển thị theo Finder (localized)
                let displayName = FileManager.default.displayName(atPath: fileURL.path)
                    .replacingOccurrences(of: ".app", with: "", options: .caseInsensitive)
                
                // Lấy icon
                let icon = NSWorkspace.shared.icon(forFile: fileURL.path)
                icon.size = NSSize(width: 32, height: 32)
                
                allApps.append(
                    InstalledApp(
                        name: displayName,
                        bundleID: bundleID,
                        icon: icon,
                        path: fileURL.path
                    )
                )
            }
        }
        
        // 🔤 Sắp xếp A-Z theo tên hiển thị
        return allApps
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }


    // MARK: - Persistence helper
    func save() {
        ConfigStore.shared.save(self.lockedApps)
    }

    // MARK: - SHA helper
    private func computeSHA(for executablePath: String) -> String? {
        let fh: FileHandle
        do {
            fh = try FileHandle(forReadingFrom: URL(fileURLWithPath: executablePath))
        } catch {
            return nil
        }
        defer { try? fh.close() }
        
        var hasher = SHA256()
        while true {
            let chunkData = fh.readData(ofLength: 64 * 1024) // 64KB
            if chunkData.isEmpty { break }
            hasher.update(data: chunkData)
        }
        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
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
                guard let sha = computeSHA(for: execPath) else {
                    NSLog("❌ Cannot compute SHA for \(execPath)")
                    continue
                }
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

// MARK: - Auto SHA Rescan
extension LockES {
    func startPeriodicRescan(interval: TimeInterval = 300) {
        // chỉ chạy 1 timer duy nhất
        if periodicTimer != nil { return }
        
        periodicTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            self.rescanLockedApps()
        }
        RunLoop.current.add(periodicTimer!, forMode: .common)
        Logfile.core.info("Start periodic SHA scanning every\(Int(interval))seconds")
    }

    func stopPeriodicRescan() {
        periodicTimer?.invalidate()
        periodicTimer = nil
    }

    @objc func rescanLockedApps() {
        Logfile.core.info("Re-scanning the SHA of locked apps...")
        var changed = false
        var updatedMap = lockedApps

        for (path, cfg) in lockedApps {
            let exeFile = cfg.execFile ?? "Unknown"
            let execPath = "\(path)/Contents/MacOS/\(exeFile)"
            guard FileManager.default.fileExists(atPath: execPath) else { continue }
            
            guard let newSHA = computeSHA(for: execPath), !newSHA.isEmpty else {
                continue
            }

            if   cfg.sha256 != newSHA {
                let name = cfg.name ?? "Unknown"
                let oldHash = cfg.sha256
                Logfile.core.warning("SHA changes for \(name): \(oldHash.prefix(8)) → \(newSHA.prefix(8))")
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
            Logfile.core.info("New SHA updated")
        } else {
            Logfile.core.info("No SHA changes")
        }
    }
}
