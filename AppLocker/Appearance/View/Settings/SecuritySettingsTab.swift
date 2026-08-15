//
//  SecuritySettingsTab.swift
//  AppLocker
//
//  Created by Doe Phương on 18/8/25.
//

import ServiceManagement
import SwiftUI

struct SecuritySettingsTab: View {
    let isMock: Bool

    @ObservedObject private var installer = ExtensionInstaller.shared
    @State private var isProtectionEnabled: Bool = !AppState.shared.manager.isProtectionDisabled
    @AppStorage("batchAuthCountdownSeconds") private var authCountdownSeconds: Double = 30
    @AppStorage("autoLockTimeoutMinutes") private var autoLockTimeoutMinutes: Int = 0

    init(isMock: Bool = false) {
        self.isMock = isMock
    }

    var body: some View {
        Form {
            Section(header: Text("Application Lock Protection")) {
                Toggle("Application Lock", isOn: Binding(
                    get: { isProtectionEnabled && (isMock || installer.isInstalled) },
                    set: { newValue in
                        handleLockToggle(newValue: newValue)
                    }
                ))
                .disabled(!isMock && !installer.isInstalled)

                HStack {
                    if !isMock && !installer.isInstalled {
                        Text("System Extension is disabled. Please enable it in System Settings.")
                            .font(.caption)
                            .foregroundColor(.red)
                        Spacer()
                        Button(action: {
                            SMAppService.openSystemSettingsLoginItems()
                            ExtensionInstaller.shared.install()
                        }, label: {
                            Text("Enable Extension")
                        })
                        .controlSize(.small)
                    } else {
                        Text(isProtectionEnabled ? "Application Lock is enabled"
                             : "Application Lock is disabled")
                            .font(.caption)
                            .foregroundColor(isProtectionEnabled ? .green : .red)
                    }
                }
            }

            Section(header: Text("Authentication Popup Timeout")) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Popup Countdown:")
                        Spacer()
                        Text("\(Int(authCountdownSeconds)) seconds")
                            .foregroundColor(.secondary)
                    }
                    Slider(value: $authCountdownSeconds, in: 10...60, step: 5)
                }
            }

            Section(header: Text("Auto-Lock Duration")) {
                Picker("Lock Session Timeout", selection: $autoLockTimeoutMinutes) {
                    Text("Immediately").tag(0)
                    Text("After 5 minutes").tag(5)
                    Text("After 15 minutes").tag(15)
                    Text("When System Sleeps").tag(-1)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            syncProtectionStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willBecomeActiveNotification)) { _ in
            syncProtectionStatus()
        }
    }

    private func syncProtectionStatus() {
        guard !isMock else { return }
        isProtectionEnabled = !AppState.shared.manager.isProtectionDisabled
    }

    private func handleLockToggle(newValue: Bool) {
        guard !isMock else {
            isProtectionEnabled = newValue
            return
        }

        if newValue == false {
            AuthenticationManager.authenticate(
                reason: String(localized: "disable application lock")
            ) { success, _ in
                DispatchQueue.main.async {
                    if success {
                        AppState.shared.manager.setProtectionDisabled(true)
                        self.isProtectionEnabled = false
                    } else {
                        self.isProtectionEnabled = true
                    }
                }
            }
        } else {
            AppState.shared.manager.setProtectionDisabled(false)
            self.isProtectionEnabled = true
        }
    }
}

#Preview {
    SecuritySettingsTab(isMock: true)
}
