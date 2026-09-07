//
//  SecuritySettingsTab.swift
//  AppLocker
//
//  Created by Doe Phương on 18/8/25.
//

import ServiceManagement
import SwiftUI

struct SecuritySettingsTab: View {
    @Binding var isUnlocked: Bool
    let isMock: Bool

    private var installer = ExtensionInstaller.shared
    @State private var isProtectionEnabled: Bool = !AppState.shared.manager.isProtectionDisabled
    @State private var allowIncomingCalls: Bool = true
    @State private var autoLockTimeoutMinutes: Int = 0
    @State private var isAuthenticating: Bool = false
    @AppStorage("batchAuthCountdownSeconds") private var authCountdownSeconds: Double = 30

    init(isUnlocked: Binding<Bool> = .constant(false), isMock: Bool = false) {
        self._isUnlocked = isUnlocked
        self.isMock = isMock
    }

    var body: some View {
        Group {
            if isUnlocked || isMock {
                unlockedContent
            } else {
                lockedStateView
            }
        }
        .task {
            syncProtectionStatus()
        }
        .onDisappear {
            if !isMock {
                isUnlocked = false
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willBecomeActiveNotification)) { _ in
            syncProtectionStatus()
        }
    }

    private var lockedStateView: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "lock.fill")
                .font(.system(size: 44, weight: .regular))
                .foregroundStyle(.secondary)

            Text("Unlock to view security settings")
                .font(.body)
                .foregroundStyle(.secondary)

            Button(action: unlockSecurityTab) {
                Text("Unlock")
                    .padding(.horizontal, 8)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var unlockedContent: some View {
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
                            .foregroundStyle(.red)
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
                            .foregroundStyle(isProtectionEnabled ? .green : .red)
                    }
                }

                Text("Temporarily pause or activate protection for all applications in your lock list.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(header: Text("Authentication Popup Timeout")) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Popup Countdown:")
                        Spacer()
                        Text("\(Int(authCountdownSeconds)) seconds")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .contentTransition(.numericText(value: authCountdownSeconds))
                            .animation(.snappy(duration: 0.2), value: authCountdownSeconds)
                    }
                    Slider(value: $authCountdownSeconds, in: 10...60, step: 5)
                }

                Text("Duration before authentication prompt automatically cancels and aborts app launch.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(header: Text("Auto-Lock Duration")) {
                Picker("Lock Session Timeout", selection: Binding(
                    get: { autoLockTimeoutMinutes },
                    set: { newValue in
                        handleAutoLockTimeoutChange(newValue: newValue)
                    }
                )) {
                    Text("Immediately").tag(0)
                    Text("After 5 minutes").tag(5)
                    Text("After 15 minutes").tag(15)
                    Text("When System Sleeps").tag(-1)
                }

                Text("Duration an app stays unlocked after authentication before requiring password again.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(header: Text("Incoming Calls")) {
                Toggle("Allow Incoming Calls while Locked", isOn: Binding(
                    get: { allowIncomingCalls },
                    set: { newValue in
                        handleIncomingCallsToggle(newValue: newValue)
                    }
                ))

                Text("Automatically allow FaceTime and Phone to receive incoming calls without password.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if !isMock {
                    Button(action: lockSecurityTab) {
                        Label("Lock", systemImage: "lock.open.fill")
                    }
                    .help("Lock security settings")
                }
            }
        }
    }

    private func syncProtectionStatus() {
        guard !isMock else { return }
        isProtectionEnabled = !AppState.shared.manager.isProtectionDisabled
        allowIncomingCalls = AppState.shared.manager.allowIncomingCalls
        autoLockTimeoutMinutes = AppState.shared.manager.autoLockTimeoutMinutes
    }

    private func unlockSecurityTab() {
        guard !isAuthenticating else { return }
        isAuthenticating = true
        AuthenticationManager.authenticate(
            reason: String(localized: "unlock security settings")
        ) { success, _ in
            self.isAuthenticating = false
            if success {
                withAnimation(.snappy(duration: 0.3)) {
                    self.isUnlocked = true
                }
            }
        }
    }

    private func lockSecurityTab() {
        withAnimation(.snappy(duration: 0.3)) {
            isUnlocked = false
        }
    }

    private func handleLockToggle(newValue: Bool) {
        if !newValue {
            let confirmation = AlertShow.show(
                title: String(localized: "Turn Off Application Lock?"),
                message: String(localized: """
                    Disabling protection will allow all locked applications to be opened without authentication.

                    Are you sure you want to turn off protection?
                    """),
                style: .critical,
                buttons: [String(localized: "Turn Off"), String(localized: "Cancel")],
                cancelIndex: 1,
                defaultIndex: 1
            )

            guard case .button(index: 0, _) = confirmation else {
                Logfile.app.info("[SecuritySettings] User cancelled turning off application lock")
                isProtectionEnabled = false
                Task { @MainActor in
                    self.isProtectionEnabled = true
                }
                return
            }
        }

        isProtectionEnabled = newValue
        guard !isMock else { return }
        AppState.shared.manager.setProtectionDisabled(!newValue)
    }

    private func handleAutoLockTimeoutChange(newValue: Int) {
        autoLockTimeoutMinutes = newValue
        guard !isMock else { return }
        AppState.shared.manager.setAutoLockTimeoutMinutes(newValue)
    }

    private func handleIncomingCallsToggle(newValue: Bool) {
        allowIncomingCalls = newValue
        guard !isMock else { return }
        AppState.shared.manager.setAllowIncomingCalls(newValue)
    }
}

#Preview {
    SecuritySettingsTab(isMock: true)
}
