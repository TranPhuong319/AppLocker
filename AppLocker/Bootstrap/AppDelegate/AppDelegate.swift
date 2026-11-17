//
//  AppDelegate.swift
//  AppLocker
//
//  Created by Doe Phương on 24/7/25.
//

import AppKit
import Foundation
import ServiceManagement

enum AgentAction {
    case install
    case uninstall
    case check
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    static let plistName = "com.TranPhuong319.AppLocker.agent"

    let menuBarController = MenuBarController()
    var hotkey: HotKeyManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" ||
           ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PLAYGROUNDS"] == "1" {
            Logfile.app.info("[Bootstrap] Running in Xcode Previews. Skipping system bootstrap.")
            return
        }

        // Build-in Relaunch Wait: Check for -waitForPID argument
        let args = CommandLine.arguments
        Logfile.app.debug("[Bootstrap] Launch Arguments: \(args, privacy: .public)")

        if let index = args.firstIndex(of: "-waitForPID"),
            index + 1 < args.count,
            let pidString = args[index + 1] as String?,
            let parentProcessID = Int32(pidString) {

            Logfile.app.debug("[Bootstrap] Waiting for PID: \(parentProcessID, privacy: .public) to exit...")

            Task(priority: .high) { [weak self] in
                var attempts = 0
                while kill(parentProcessID, 0) == 0 && attempts < 30 {
                    try? await Task.sleep(for: .milliseconds(100))
                    attempts += 1
                }
                if attempts >= 30 {
                    Logfile.app.warning("[Bootstrap] Wait timed out after 3 seconds. Proceeding anyway.")
                } else {
                    Logfile.app.debug("[Bootstrap] Parent process exited.")
                }
                self?.enforceSingleInstance(ignoringPID: parentProcessID)
                await self?.finishLaunchSetup()
            }
        } else {
            enforceSingleInstance()
            Task { @MainActor [weak self] in
                await self?.finishLaunchSetup()
            }
        }
    }

    @MainActor
    private func finishLaunchSetup() async {

#if !DEBUG
        checkAndMoveToApplications()
#endif

        Logfile.app.info("[Bootstrap] AppLocker v\(Bundle.main.fullVersion, privacy: .public) starting...")

        let isFirstStart = UserDefaults.standard.object(forKey: "isFirstStart") as? Bool ?? true

#if !DEBUG
        if !isLaunchedByLaunchd && !isFirstStart {
            if await handoverToLaunchdIfManual() {
                return
            }
        }
#endif

        let theme = UserDefaults.standard.string(forKey: "appTheme") ?? "System"
        applyTheme(theme)
        setupEditMenu()

        if isFirstStart {
            Logfile.app.info("[Bootstrap] First launch. Showing welcome/ToS screen.")
            WelcomeWindowController.show()
        } else {
            Logfile.app.info("[Bootstrap] Not first launch. Running normal launch configuration.")
            launchConfig()
        }
    }

#if !DEBUG
    @MainActor
    private func handoverToLaunchdIfManual() async -> Bool {
        Logfile.app.info("[Bootstrap] App launched manually. Checking launchctl handover...")
        let decision = await LaunchBootstrapPolicy.resolveHandover(
            isAgentActive: { isAgentActive },
            installAgent: {
                Logfile.app.info("[Bootstrap] Agent not loaded in launchctl. Registering...")
                _ = manageAgent(action: .install)
            },
            kickstart: { [self] in
                await runLaunchctlKickstart(timeout: .seconds(3))
            },
            forceReRegister: { [self] in
                Logfile.app.warning("[Bootstrap] Initial launchctl kickstart failed. Force re-registering agent...")
                return forceReRegisterAgent()
            }
        )

        switch decision {
        case .terminateManualAndHandover:
            Logfile.app.notice("[Bootstrap] Handed over to launchd instance. Terminating manual launcher.")
            NSApp.terminate(nil)
            return true
        case .continueManual:
            let statusDesc = SMAppService.agent(plistName: "\(Self.plistName).plist").status.description
            Logfile.app.warning(
                """
                [Bootstrap] Could not hand over to launchctl (status=\(statusDesc, privacy: .public)). \
                Continuing to run current manual instance directly.
                """
            )
            return false
        }
    }
#endif

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            openAppList()
        }
        return true
    }

    private(set) var currentThemeAppearance: NSAppearance?

    static func appearance(for theme: String) -> NSAppearance? {
        switch theme {
        case "Light":
            return NSAppearance(named: .aqua)
        case "Dark":
            return NSAppearance(named: .darkAqua)
        default:
            return nil
        }
    }

    func applyTheme(_ theme: String) {
        let appearance = Self.appearance(for: theme)
        currentThemeAppearance = appearance

        NSApp.appearance = nil
        menuBarController.applyAppearance(appearance)

        for window in NSApp.windows {
            guard window !== menuBarController.statusItemWindow else { continue }
            window.appearance = appearance
        }
    }

    func setupEditMenu() {
        guard NSApp.mainMenu == nil else { return }

        let mainMenu = NSMenu()
        mainMenu.addItem(createAppMenuItem())
        mainMenu.addItem(createEditMenuItem())
        mainMenu.addItem(createWindowMenuItem())
        NSApp.mainMenu = mainMenu
    }

    private func createAppMenuItem() -> NSMenuItem {
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(
            withTitle: String(localized: "About AppLocker"), action: #selector(showAboutWindow), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(
            withTitle: String(localized: "Settings") + "…", action: #selector(openSettings), keyEquivalent: ",")
        appMenu.addItem(.separator())
        appMenu.addItem(
            withTitle: String(localized: "Hide AppLocker"),
            action: #selector(NSApplication.hide(_:)),
            keyEquivalent: "h")
        appMenu.addItem(
            withTitle: String(localized: "Hide Others"),
            action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h")
        appMenu.addItem(
            withTitle: String(localized: "Show All"),
            action: #selector(NSApplication.unhideAllApplications(_:)),
            keyEquivalent: "")
        #if DEBUG
        appMenu.addItem(.separator())
        appMenu.addItem(
            withTitle: String(localized: "Quit AppLocker"),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q")
        #endif
        appMenuItem.submenu = appMenu
        return appMenuItem
    }

    private func createEditMenuItem() -> NSMenuItem {
        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: String(localized: "Edit"))
        editMenu.addItem(
            withTitle: String(localized: "Undo"), action: #selector(UndoRedoResponder.undo(_:)), keyEquivalent: "z")
        editMenu.addItem(
            withTitle: String(localized: "Redo"), action: #selector(UndoRedoResponder.redo(_:)), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: String(localized: "Cut"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: String(localized: "Copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: String(localized: "Paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(
            withTitle: String(localized: "Select All"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        return editMenuItem
    }

    private func createWindowMenuItem() -> NSMenuItem {
        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: String(localized: "Window"))
        windowMenu.addItem(
            withTitle: String(localized: "Close Window"),
            action: #selector(NSWindow.performClose(_:)),
            keyEquivalent: "w")
        windowMenuItem.submenu = windowMenu
        return windowMenuItem
    }

    func enforceSingleInstance(ignoringPID: Int32? = nil) {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }

        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        let decision = LaunchBootstrapPolicy.resolveSingleInstance(
            isLaunchedByLaunchd: isLaunchedByLaunchd,
            currentPID: ProcessInfo.processInfo.processIdentifier,
            ignoringPID: ignoringPID,
            runningPIDs: apps.map(\.processIdentifier)
        )

        switch decision {
        case .proceed:
            return
        case .terminateOtherManualInstances(let otherPIDs):
            Logfile.app.info(
                """
                [Bootstrap] Launchd instance taking over from manual instance(s) \
                (PIDs: \(otherPIDs, privacy: .public)).
                """
            )
            apps.filter { otherPIDs.contains($0.processIdentifier) }.forEach { $0.terminate() }
        case .activateAndTerminateSelf(let targetPID):
            Logfile.app.warning(
                """
                [Bootstrap] Another instance is running \
                (PIDs: \([targetPID], privacy: .public)). \
                Activating existing instance and terminating this new instance.
                """
            )
            apps.first(where: { $0.processIdentifier == targetPID })?.activate()
            NSApp.terminate(nil)
        }
    }
}

extension SMAppService.Status {
    public var description: String {
        switch self {
        case .notRegistered: return "notRegistered"
        case .enabled: return "enabled"
        case .requiresApproval: return "requiresApproval"
        case .notFound: return "notFound"
        default: return "unknown(\(rawValue))"
        }
    }
}

extension NSApplication {
    var appDelegate: AppDelegate? {
        delegate as? AppDelegate
    }
}

@objc private protocol UndoRedoResponder {
    func undo(_ sender: Any?)
    func redo(_ sender: Any?)
}
