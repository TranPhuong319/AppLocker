//
//  SettingsView.swift
//  AppLocker
//
//  Created by Doe Phương on 18/8/25.
//

import SwiftUI

struct SettingsView: View {
    @State private var selectedTab: SettingsTab = .general
    private var isMock: Bool

    @State private var isAgentActive: Bool = true
    @State private var hasAvailableUpdate: Bool = false
    @State private var availableUpdateVersion: String = ""
    @State private var isProtectionEnabled: Bool = !AppState.shared.manager.isProtectionDisabled

    init(
        selectedTab: SettingsTab = .general,
        isMock: Bool = false
    ) {
        _selectedTab = State(initialValue: selectedTab)
        self.isMock = isMock
    }

    var body: some View {
        NavigationSplitView {
            List(SettingsTab.allCases, id: \.self, selection: $selectedTab) { tab in
                Label {
                    Text(tab.displayName)
                        .font(.system(size: 13, weight: .medium))
                } icon: {
                    Image(systemName: tab.iconName)
                        .foregroundColor(.blue)
                }
                .tag(tab)
            }
            .listStyle(.sidebar)
            .navigationTitle(String(localized: "Settings"))
        } detail: {
            detailContent(for: selectedTab)
                .navigationTitle(selectedTab.displayName)
                .padding(.top, -25)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .navigationSplitViewStyle(.automatic)
        .frame(minWidth: 600, minHeight: 400)
        .onAppear {
            checkAgentStatus()
            updateSparkleStatus()
            if !isMock {
                isProtectionEnabled = !AppState.shared.manager.isProtectionDisabled
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willBecomeActiveNotification)) { _ in
            if !isMock {
                isProtectionEnabled = !AppState.shared.manager.isProtectionDisabled
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .appLockerPendingUpdateDidChange)) { _ in
            updateSparkleStatus()
        }
    }

    @ViewBuilder
    private func detailContent(for tab: SettingsTab) -> some View {
        switch tab {
        case .general:
            GeneralSettingsTab(isAgentActive: $isAgentActive, isMock: isMock)
        case .security:
            SecuritySettingsTab(isProtectionEnabled: $isProtectionEnabled, isMock: isMock)
        case .updates:
            UpdatesSettingsTab(
                hasAvailableUpdate: $hasAvailableUpdate,
                availableUpdateVersion: $availableUpdateVersion,
                isMock: isMock
            )
        case .appearance:
            AppearanceSettingsTab(isMock: isMock)
        }
    }

    private func checkAgentStatus() {
        guard !isMock else {
            isAgentActive = true
            return
        }
        if let appDelegate = NSApp.delegate as? AppDelegate {
            isAgentActive = appDelegate.checkAgentStatus()
        }
    }

    private func updateSparkleStatus() {
        guard !isMock, let appDelegate = NSApp.delegate as? AppDelegate else { return }
        if let update = appDelegate.pendingUpdate {
            hasAvailableUpdate = true
            let displayVer = update.displayVersionString
            let buildVer = update.versionString
            if displayVer != buildVer {
                availableUpdateVersion = "\(displayVer) (\(buildVer))"
            } else {
                availableUpdateVersion = displayVer
            }
        } else {
            hasAvailableUpdate = false
            availableUpdateVersion = ""
        }
    }
}

#Preview {
    SettingsView(isMock: true)
}
