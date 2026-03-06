//
//  ESManager+Config.swift
//  ESExtension
//
//  Created by Antigravity on 06/02/26.
//

import Foundation
import os

extension ESManager {
    static let configPath = "/Users/Shared/AppLocker/config.plist"
    
    /// Đọc cấu hình từ file và cập nhật vào bộ nhớ
    func loadInitialConfig() {
        backgroundProcessingQueue.async { [weak self] in
            guard let self = self else { return }
            
            let url = URL(fileURLWithPath: ESManager.configPath)
            guard FileManager.default.fileExists(atPath: url.path) else {
                Logfile.endpointSecurity.log("Config file not found at \(ESManager.configPath). Skipping initial load.")
                return
            }
            
            do {
                let data = try Data(contentsOf: url, options: .mappedIfSafe)
                let decoder = PropertyListDecoder()
                
                // Cấu trúc: [UID_String: [LockedAppConfig]]
                let rawConfig = try decoder.decode([String: [LockedAppConfig]].self, from: data)
                
                var newBlockedSHAs: [uid_t: Set<String>] = [:]
                var newPathToSHA: [String: String] = [:]
                
                for (uidString, apps) in rawConfig {
                    guard let uid = uid_t(uidString) else { continue }
                    var shaSet = Set<String>()
                    for app in apps {
                        shaSet.insert(app.sha256)
                        newPathToSHA[app.path] = app.sha256
                    }
                    newBlockedSHAs[uid] = shaSet
                }
                
                // Atomic Swap
                self.stateLock.perform {
                    self.blockedSHAs = newBlockedSHAs
                    self.blockedPathToSHA.merge(newPathToSHA) { (_, new) in new }
                }
                
                let totalApps = newBlockedSHAs.values.reduce(0) { $0 + $1.count }
                Logfile.endpointSecurity.log("ESManager: Loaded \(totalApps) apps for \(newBlockedSHAs.count) users from config.")
                
            } catch {
                Logfile.endpointSecurity.error("ESManager: Failed to load config: \(error.localizedDescription)")
            }
        }
    }
    
    /// Theo dõi thay đổi của file cấu hình
    func startConfigMonitoring() {
        let fileDescriptor = open(ESManager.configPath, O_EVTONLY)
        guard fileDescriptor != -1 else {
            Logfile.endpointSecurity.error("ESManager: Failed to open config file for monitoring.")
            // Thử lại sau nếu file chưa tồn tại
            backgroundProcessingQueue.asyncAfter(deadline: .now() + 5) { [weak self] in
                self?.startConfigMonitoring()
            }
            return
        }
        
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .delete, .rename],
            queue: backgroundProcessingQueue
        )
        
        var debounceTimer: DispatchSourceTimer?
        
        source.setEventHandler { [weak self] in
            let event = source.data
            if event.contains(.delete) || event.contains(.rename) {
                Logfile.endpointSecurity.warning("Config file deleted or renamed. Restarting monitor...")
                source.cancel()
                return
            }
            
            // Debounce logic: Đợi 500ms sau lần thay đổi cuối cùng
            debounceTimer?.cancel()
            let timer = DispatchSource.makeTimerSource(queue: self?.backgroundProcessingQueue)
            timer.schedule(deadline: .now() + 0.5)
            timer.setEventHandler {
                self?.loadInitialConfig()
                timer.cancel()
            }
            timer.resume()
            debounceTimer = timer
        }
        
        source.setCancelHandler {
            close(fileDescriptor)
            // Tự động khởi động lại trình theo dõi (vì file có thể bị ghi đè/xóa tạm thời)
            DispatchQueue.global().asyncAfter(deadline: .now() + 1) { [weak self] in
                self?.startConfigMonitoring()
            }
        }
        
        source.resume()
        Logfile.endpointSecurity.log("ESManager: Started monitoring \(ESManager.configPath)")
    }
}
