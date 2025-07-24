import Foundation
import AppKit

class LockedAppsManager: ObservableObject {
    @Published var lockedApps: [String] = []
    
    private var configFile: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appFolder = appSupport.appendingPathComponent("AppLocker", isDirectory: true)
        if !FileManager.default.fileExists(atPath: appFolder.path) {
            try? FileManager.default.createDirectory(at: appFolder, withIntermediateDirectories: true)
        }
        return appFolder.appendingPathComponent("locked_apps.json")
    }
    
    private var currentBundleFile: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("AppLocker/.current_bundle")
    }
    
    init() {
        load()
    }
    
    func load() {
        if !FileManager.default.fileExists(atPath: configFile.path) {
            lockedApps = []
            save()
            return
        }
        do {
            let data = try Data(contentsOf: configFile)
            lockedApps = try JSONDecoder().decode([String].self, from: data)
        } catch {
            print("⚠️ Không thể load file config: \(error.localizedDescription)")
            lockedApps = []
        }
    }
    
    func save() {
        DispatchQueue.global(qos: .utility).async { [self] in
            let dirURL = configFile.deletingLastPathComponent()
            do {
                try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
                if FileManager.default.fileExists(atPath: configFile.path) {
                    _ = shell("chflags nouchg '\(configFile.path)'")
                }
                let data = try JSONEncoder().encode(lockedApps)
                try data.write(to: configFile)
                _ = shell("chflags uchg '\(configFile.path)'")
            } catch {
                DispatchQueue.main.async {
                    let alert = NSAlert()
                    alert.messageText = "Không lưu được cấu hình"
                    alert.informativeText = error.localizedDescription
                    alert.alertStyle = .critical
                    alert.addButton(withTitle: "OK")
                    alert.runModal()
                }
            }
        }
    }
    
    func toggleLock(for bundleID: String) {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            print("⚠️ Không tìm thấy app: \(bundleID)")
            return
        }

        let macOSDir = appURL.appendingPathComponent("Contents/MacOS")

        let execName: String
        do {
            let contents = try FileManager.default.contentsOfDirectory(atPath: macOSDir.path)

            if contents.count == 1 {
                execName = contents[0]
            } else {
                let infoPlist = appURL.appendingPathComponent("Contents/Info.plist")
                let data = try Data(contentsOf: infoPlist)
                if let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
                   let exec = plist["CFBundleExecutable"] as? String {
                    execName = exec
                } else {
                    print("⚠️ Không thể đọc CFBundleExecutable từ Info.plist")
                    return
                }
            }
        } catch {
            print("⚠️ Lỗi khi truy cập MacOS dir hoặc Info.plist: \(error)")
            return
        }

        let origExe = macOSDir.appendingPathComponent(execName)
        let realExe = macOSDir.appendingPathComponent("\(execName).real")

        guard let stubURL = Bundle.main.url(forResource: "Launcher", withExtension: nil) else {
            print("⚠️ Không tìm thấy Launcher trong bundle")
            return
        }
        
        if lockedApps.contains(bundleID) {
            // 🔓 Unlock: Restore original executable and clean marker file
            let tasks = [
                // ✅ Chỉ tiếp tục nếu .real tồn tại
                "[ -f '\(realExe.path)' ] || exit 1",

                // ❌ Xóa stub
                "rm -f '\(origExe.path)'",

                // ✅ Đổi tên lại bản gốc
                "mv '\(realExe.path)' '\(origExe.path)'",

                // ✅ Cấp quyền thực thi
                "chmod +x '\(origExe.path)'",

                // ✅ Xóa marker
                "rm -f '\(currentBundleFile.path)'"
            ]
	

            if executeAdminTasks(tasks) {
                lockedApps.removeAll { $0 == bundleID }
                save()
                print("🔓 Đã mở khóa \(bundleID)")
                if !FileManager.default.fileExists(atPath: realExe.path) {
                    print("⚠️ Không tìm thấy file .real để phục hồi.")
                    return
                }
                print("origExe.path: \(origExe.path)")
                print("realExe.path: \(realExe.path)")
                print("currentBundleFile.path: \(currentBundleFile.path)")


            }
        } else {
            // 🔒 Lock: Replace executable with stub and mark current bundle
            let escapedBundleID = bundleID.replacingOccurrences(of: "'", with: "'\\''")
            let tempFile = URL(fileURLWithPath: "/tmp/current_bundle")
            try? escapedBundleID.write(to: tempFile, atomically: true, encoding: .utf8)
            
            let tasks = [
                "echo \(escapedBundleID) > '\(currentBundleFile.path)'",
                "mv '\(origExe.path)' '\(realExe.path)'",
                "cp '\(stubURL.path)' '\(origExe.path)'",
                "chmod +x '\(origExe.path)'"
            ]
            
            if executeAdminTasks(tasks) {
                lockedApps.append(bundleID)
                save()
                print("🔒 Đã khóa \(bundleID)")
            }
        }
    }
    
    func isLocked(_ bundleID: String) -> Bool {
        lockedApps.contains(bundleID)
    }
    
    @discardableResult
    private func executeAdminTasks(_ tasks: [String]) -> Bool {
        let script = tasks.joined(separator: " && ")
        let fullScript = "do shell script \"\(script)\" with administrator privileges"

        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: fullScript) {
            let result = appleScript.executeAndReturnError(&error)

            if let error = error {
                DispatchQueue.main.async {
                    let alert = NSAlert()
                    alert.messageText = "Lỗi yêu cầu quyền admin"
                    alert.informativeText = "Mật khẩu admin không đúng hoặc đã bị hủy. Chi tiết: \(error)"
                    alert.alertStyle = .critical
                    alert.addButton(withTitle: "OK")
                    alert.runModal()
                }
                print("❌ AppleScript error: \(error)")
                return false
            }

            print("✅ AppleScript executed: \(result.stringValue ?? "(no output)")")
            return true
        }

        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Lỗi thực thi AppleScript"
            alert.informativeText = "Không thể khởi tạo AppleScript."
            alert.alertStyle = .critical
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
        return false
    }

    
    @discardableResult
    func shell(_ command: String) -> String {
        let task = Process()
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        task.arguments = ["-c", command]
        task.launchPath = "/bin/zsh"
        try? task.run()
        task.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
