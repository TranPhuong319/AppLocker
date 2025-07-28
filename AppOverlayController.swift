//
//  MARK: AppOverlayController.swift
//  AppLocker
//
//  Created by Doe Phương on 24/07/2025.
//


//
//  MARK: AppOverlayController.swift
//  AppLocker
//
//  Created by Doe Phương on 24/07/2025.
//


import Cocoa
import ApplicationServices
import LocalAuthentication

class AppOverlayController {
    var frameSyncTimers: [pid_t: Timer] = [:]
    private var overlays: [AXUIElement: NSWindow] = [:]
    private var overlayWindows: [pid_t: [NSWindow]] = [:]  // Mới thêm
    private var observer: AXObserver?
    private var pidWindowMap: [pid_t: [AXUIElement]] = [:]

    func observeAppTermination(for pid: pid_t) {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.processIdentifier == pid else {
                return
            }

            print("App với PID \(pid) đã tắt, xoá overlay.")
            self?.removeOverlays(for: pid)
        }
    }

    func startObservingAppWindows(for pid: pid_t) {
        let appRef = AXUIElementCreateApplication(pid)

        var value: AnyObject?
        if AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &value) == .success,
           let windowList = value as? [AXUIElement] {
            pidWindowMap[pid] = windowList
            overlayWindows[pid] = []

            for window in windowList {
                let overlay = attachOverlay(to: window)
                if let overlay = overlay {
                    overlayWindows[pid]?.append(overlay)
                }
            }
        }

        // AXObserver
        let callback: AXObserverCallback = { observer, element, notification, context in
            let controller = Unmanaged<AppOverlayController>.fromOpaque(context!).takeUnretainedValue()
            controller.handleAXNotification(element: element, notification: notification as String)
        }

        var newObserver: AXObserver?
        if AXObserverCreate(pid, callback, &newObserver) == .success, let observer = newObserver {
            self.observer = observer
            let runLoopSource = AXObserverGetRunLoopSource(observer)
            CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .defaultMode)

            let notifications = [
                kAXWindowCreatedNotification,
                kAXWindowMiniaturizedNotification,
                kAXWindowDeminiaturizedNotification,
                kAXMovedNotification,
                kAXResizedNotification
            ]

            for notif in notifications {
                AXObserverAddNotification(observer, appRef, notif as CFString, Unmanaged.passUnretained(self).toOpaque())
            }

            observeAppTermination(for: pid)
        }
    }

    private func handleAXNotification(element: AXUIElement, notification: String) {
        switch notification {
        case kAXWindowCreatedNotification:
            if let overlay = attachOverlay(to: element),
               let pid = pidForElement(element) {
                overlays[element] = overlay
                overlayWindows[pid, default: []].append(overlay)
                pidWindowMap[pid, default: []].append(element)
            }
        case kAXWindowMiniaturizedNotification:
            overlays[element]?.orderOut(nil)
        case kAXWindowDeminiaturizedNotification:
            overlays[element]?.orderFront(nil)
        case kAXMovedNotification, kAXResizedNotification:
            if let overlay = overlays[element], let newFrame = getWindowFrame(element) {
                overlay.setFrame(newFrame, display: true)
            }
        default:
            break
        }
    }
    
    func startFrameSync(for pid: pid_t) {
        frameSyncTimers[pid]?.invalidate() // Clear nếu đã tồn tại

        frameSyncTimers[pid] = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self = self,
                  let elements = self.pidWindowMap[pid] else { return }

            for element in elements {
                if let overlay = self.overlays[element],
                   let newFrame = self.getWindowFrame(element) {
                    overlay.setFrame(newFrame, display: true)
                }
            }
        }
    }

    func stopFrameSync(for pid: pid_t) {
        frameSyncTimers[pid]?.invalidate()
        frameSyncTimers.removeValue(forKey: pid)
    }

    private func attachOverlay(to axWindow: AXUIElement) -> NSWindow? {
        guard let windowFrame = getWindowFrame(axWindow) else { return nil }

        let overlay = NSWindow(
            contentRect: windowFrame,
            styleMask: [],
            backing: .buffered,
            defer: false
        )

        overlay.isReleasedWhenClosed = false
        overlay.backgroundColor = NSColor.black.withAlphaComponent(0.6)
        overlay.level = .floating // .mainMenu + 2
        overlay.ignoresMouseEvents = false
        overlay.isOpaque = false
        overlay.hasShadow = false
        overlay.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, stationary]
        overlay.title = "Overlay"

        overlay.makeKeyAndOrderFront(nil)
        overlays[axWindow] = overlay
        return overlay
    }

    private func getWindowFrame(_ window: AXUIElement) -> NSRect? {
        var position: CFTypeRef?
        var size: CFTypeRef?

        let posOK = AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &position)
        let sizeOK = AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &size)

        guard posOK == .success,
              sizeOK == .success,
              let pos = position,
              let sz = size,
              CFGetTypeID(pos) == AXValueGetTypeID(),
              CFGetTypeID(sz) == AXValueGetTypeID()
        else {
            return nil
        }

        var point = CGPoint.zero
        var szStruct = CGSize.zero

        AXValueGetValue(unsafeBitCast(pos, to: AXValue.self), .cgPoint, &point)
        AXValueGetValue(unsafeBitCast(sz, to: AXValue.self), .cgSize, &szStruct)

        if let screen = NSScreen.main {
            let correctedY = screen.frame.height - point.y - szStruct.height
            return NSRect(x: point.x, y: correctedY, width: szStruct.width, height: szStruct.height)
        }

        return NSRect(origin: point, size: szStruct)
    }

    @objc private func authenticate() {
        let context = LAContext()
        var error: NSError?

        if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) {
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Xác thực để mở khóa") { success, _ in
                DispatchQueue.main.async {
                    if success {
                        print("✅ Xác thực thành công.")
                    } else {
                        print("❌ Xác thực thất bại hoặc bị huỷ.")
                    }

                    // Xoá toàn bộ overlay liên quan đến tất cả PID
                    for pid in self.pidWindowMap.keys {
                        self.removeOverlays(for: pid)
                    }
                }
            }
        } else {
            print("Không thể xác thực: \(error?.localizedDescription ?? "")")
        }
    }

    func removeOverlays(for pid: pid_t) {
        guard let windows = pidWindowMap[pid] else { return }

        for win in windows {
            if let overlay = overlays[win] {
                overlay.orderOut(nil)
                overlays.removeValue(forKey: win)
            }
        }

        if let overlaysForPid = overlayWindows[pid] {
            for window in overlaysForPid {
                window.orderOut(nil)
            }
            overlayWindows.removeValue(forKey: pid)
        }

        pidWindowMap.removeValue(forKey: pid)
    }

    func removeAllOverlays() {
        for (_, overlay) in overlays {
            overlay.orderOut(nil)
        }
        overlays.removeAll()
        pidWindowMap.removeAll()
        overlayWindows.removeAll()
    }

    private func pidForElement(_ element: AXUIElement) -> pid_t? {
        var pid: pid_t = 0
        let result = AXUIElementGetPid(element, &pid)
        return (result == .success) ? pid : nil
    }
}
