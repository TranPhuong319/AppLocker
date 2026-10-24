//
//  GeneralSettingsTab.swift
//  AppLocker
//
//  Created by Doe Phương on 18/8/25.
//

import SwiftUI

struct GeneralSettingsTab: View {
    let isMock: Bool

    @State private var isAgentActive: Bool = true
    @AppStorage("showBlockedNotifications") private var showNotifications: Bool = true

    @State private var appListShortcut: HotKeyShortcut? = HotKeyShortcut.currentAppList
    @State private var resumeProtectionShortcut: HotKeyShortcut? = HotKeyShortcut.currentResumeProtection
    @State private var isCustomized: Bool = HotKeyShortcut.isCustomized

    init(isMock: Bool = false) {
        self.isMock = isMock
    }

    var body: some View {
        Form {
            Section(header: Text("Background Security Service")) {
                HStack {
                    Label(
                        "Background Agent Status",
                        systemImage: isAgentActive ? "shield.checkered" : "exclamationmark.shield"
                    )
                    Spacer()
                    if isAgentActive {
                        Text("Active")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.green)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(Color.green.opacity(0.15))
                            )
                    } else {
                        Text("Inactive")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.red)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(Color.red.opacity(0.15))
                            )
                    }
                }

                #if DEBUG
                Toggle("Simulate Agent Active (Debug)", isOn: $isAgentActive)
                #endif

                if !isAgentActive {
                    Button(action: repairAgentService, label: {
                        Label("Repair Agent Service", systemImage: "wrench.and.screwdriver")
                    })
                    .help("Re-register launchctl agent service")
                }

                Text("Background service ensuring apps remain protected even when the main window is closed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(header: Text("Notifications")) {
                Toggle("Show notifications when an app is blocked", isOn: $showNotifications)

                Text("Show a system notification whenever an unauthorized launch attempt is blocked.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(header: Text("Keyboard Shortcuts")) {
                HStack {
                    Label("Manage the application list", systemImage: "lock.app.dashed")
                    Spacer()
                    ShortcutRecorderView(
                        shortcut: appListShortcut,
                        onSave: { newShortcut in
                            saveAppListShortcut(newShortcut)
                        }
                    )
                }

                HStack {
                    Label("Resume Protection", systemImage: "lock.fill")
                    Spacer()
                    ShortcutRecorderView(
                        shortcut: resumeProtectionShortcut,
                        onSave: { newShortcut in
                            saveResumeShortcut(newShortcut)
                        }
                    )
                }

                if isCustomized {
                    Button("Reset Shortcuts to Defaults", action: resetShortcuts)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .task {
            checkAgentStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: .hotKeySettingsDidChange)) { _ in
            appListShortcut = HotKeyShortcut.currentAppList
            resumeProtectionShortcut = HotKeyShortcut.currentResumeProtection
            isCustomized = HotKeyShortcut.isCustomized
        }
    }

    private func checkAgentStatus() {
        guard !isMock else { return }
        if let appDelegate = NSApp.appDelegate {
            isAgentActive = appDelegate.isAgentActive
        }
    }

    private func repairAgentService() {
        guard !isMock else { return }
        if let appDelegate = NSApp.appDelegate {
            isAgentActive = appDelegate.repairAgentService()
        }
    }

    private func saveAppListShortcut(_ newShortcut: HotKeyShortcut?) {
        guard !isMock else { return }
        if let newShortcut, newShortcut == resumeProtectionShortcut {
            NSSound.beep()
            return
        }
        appListShortcut = newShortcut
        HotKeyShortcut.currentAppList = newShortcut
        isCustomized = HotKeyShortcut.isCustomized
    }

    private func saveResumeShortcut(_ newShortcut: HotKeyShortcut?) {
        guard !isMock else { return }
        if let newShortcut, newShortcut == appListShortcut {
            NSSound.beep()
            return
        }
        resumeProtectionShortcut = newShortcut
        HotKeyShortcut.currentResumeProtection = newShortcut
        isCustomized = HotKeyShortcut.isCustomized
    }

    private func resetShortcuts() {
        guard !isMock else { return }
        HotKeyShortcut.resetToDefaults()
        appListShortcut = HotKeyShortcut.currentAppList
        resumeProtectionShortcut = HotKeyShortcut.currentResumeProtection
        isCustomized = false
    }
}

#Preview {
    GeneralSettingsTab(isMock: true)
}
