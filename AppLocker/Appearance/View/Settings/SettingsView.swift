//
//  SettingsView.swift
//  AppLocker
//
//  Created by Doe Phương on 18/8/25.
//

import SwiftUI

// MARK: - Settings Navigator

@Observable
@MainActor
final class SettingsNavigator {
    var selectedTab: SettingsTab {
        didSet {
            guard selectedTab != oldValue else { return }
            onTabChanged?(selectedTab, oldValue)
        }
    }

    var onTabChanged: ((SettingsTab, SettingsTab) -> Void)?

    init(selectedTab: SettingsTab = .general) {
        self.selectedTab = selectedTab
    }
}

// MARK: - Main Settings View

struct SettingsView: View {
    @Bindable var navigator: SettingsNavigator
    @State private var navigationHistory: [SettingsTab] = [.general]
    @State private var historyIndex: Int = 0
    @State private var isNavigatingHistory: Bool = false
    @State private var isSecurityUnlocked: Bool = false
    private var isMock: Bool

    init(
        navigator: SettingsNavigator = SettingsNavigator(),
        isMock: Bool = false
    ) {
        self.navigator = navigator
        self.isMock = isMock
    }

    var body: some View {
        NavigationSplitView {
            List(SettingsTab.allCases, id: \.self, selection: $navigator.selectedTab) { tab in
                HStack(spacing: 10) {
                    Label(tab.displayName, systemImage: tab.iconName)

                    if tab == .security {
                        Spacer()
                        Button(action: toggleSecurityLock) {
                            securityLockIcon
                        }
                        .buttonStyle(.plain)
                        .help(isSecurityUnlocked ? "Lock security settings" : "Unlock security settings")
                    }
                }
                .padding(.vertical, 2)
                .tag(tab)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 170, ideal: 170, max: 240)
        } detail: {
            detailContent(for: navigator.selectedTab)
                .id(navigator.selectedTab)
                .padding(.top, usesGroupedForm ? -16 : 0)
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: usesGroupedForm ? .topLeading : .center
                )
                .navigationTitle(navigator.selectedTab.displayName)
                .toolbar {
                    ToolbarItemGroup(placement: .navigation) {
                        ControlGroup {
                            Button(action: goBack) {
                                Image(systemName: "chevron.left")
                            }
                            .disabled(historyIndex <= 0)
                            .help(String(localized: "Back"))
                            .accessibilityLabel(String(localized: "Back"))

                            Button(action: goForward) {
                                Image(systemName: "chevron.right")
                            }
                            .disabled(historyIndex >= navigationHistory.count - 1)
                            .help(String(localized: "Forward"))
                            .accessibilityLabel(String(localized: "Forward"))
                        }
                        .controlGroupStyle(.navigation)
                    }
                }
        }
        .navigationSplitViewStyle(.balanced)
        .onChange(of: navigator.selectedTab) { _, newTab in
            handleTabChange(to: newTab)
        }
        .onReceive(NotificationCenter.default.publisher(for: .settingsWindowWillClose)) { _ in
            isSecurityUnlocked = false
        }
    }

    private func toggleSecurityLock() {
        if isSecurityUnlocked {
            withAnimation(.snappy(duration: 0.3)) {
                isSecurityUnlocked = false
            }
        } else if navigator.selectedTab != .security {
            navigator.selectedTab = .security
        } else {
            Task {
                do {
                    let success = try await AuthenticationManager.authenticate(
                        reason: String(localized: "unlock security settings")
                    )
                    if success {
                        withAnimation(.snappy(duration: 0.3)) {
                            isSecurityUnlocked = true
                        }
                    }
                } catch {}
            }
        }
    }

    private func handleTabChange(to newTab: SettingsTab) {
        if newTab != .security {
            isSecurityUnlocked = false
        }
        if isNavigatingHistory {
            isNavigatingHistory = false
            return
        }
        if navigationHistory.indices.contains(historyIndex), navigationHistory[historyIndex] != newTab {
            navigationHistory = Array(navigationHistory.prefix(historyIndex + 1))
            navigationHistory.append(newTab)
            historyIndex = navigationHistory.count - 1
        }
    }

    private func goBack() {
        guard historyIndex > 0 else { return }
        isNavigatingHistory = true
        historyIndex -= 1
        navigator.selectedTab = navigationHistory[historyIndex]
    }

    private func goForward() {
        guard historyIndex < navigationHistory.count - 1 else { return }
        isNavigatingHistory = true
        historyIndex += 1
        navigator.selectedTab = navigationHistory[historyIndex]
    }

    private var securityLockIcon: some View {
        Image(systemName: isSecurityUnlocked ? "lock.open.fill" : "lock.fill")
            .magicSymbolReplace()
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(isSecurityUnlocked ? .blue : .secondary)
    }

    private var usesGroupedForm: Bool {
        switch navigator.selectedTab {
        case .general, .appearance, .updates:
            return true
        case .security:
            return isSecurityUnlocked || isMock
        case .activity, .diagnostics:
            return false
        }
    }

    @ViewBuilder
    private func detailContent(for tab: SettingsTab) -> some View {
        switch tab {
        case .general:
            GeneralSettingsTab(isMock: isMock)
        case .security:
            SecuritySettingsTab(isUnlocked: $isSecurityUnlocked, isMock: isMock)
        case .activity:
            ActivitySettingsTab(isMock: isMock)
        case .appearance:
            AppearanceSettingsTab(isMock: isMock)
        case .updates:
            UpdatesSettingsTab(isMock: isMock)
        case .diagnostics:
            DiagnosticsSettingsTab(isMock: isMock)
        }
    }
}

#Preview {
    SettingsView(isMock: true)
        .frame(
            width: WindowLayout.settingsMinSize.width,
            height: WindowLayout.settingsMinSize.height
        )
}
