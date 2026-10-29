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

// MARK: - Native Window Configurator

@MainActor
private struct WindowConfigurator: NSViewRepresentable {
    let configure: @MainActor (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        Task { @MainActor in
            if let window = view.window {
                configure(window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
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

    init(
        selectedTab: SettingsTab,
        isMock: Bool = false
    ) {
        self.navigator = SettingsNavigator(selectedTab: selectedTab)
        self.isMock = isMock
    }

    var body: some View {
        NavigationSplitView {
            List(SettingsTab.allCases, id: \.self, selection: $navigator.selectedTab) { tab in
                HStack(spacing: 10) {
                    Label {
                        Text(tab.displayName)
                            .font(.system(size: 13, weight: tab == navigator.selectedTab ? .medium : .regular))
                    } icon: {
                        Image(systemName: tab.iconName)
                            .foregroundStyle(tab == navigator.selectedTab ? Color.accentColor : .secondary)
                            .frame(width: 20)
                    }

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
                .padding(.top, (navigator.selectedTab == .diagnostics || navigator.selectedTab == .activity) ? 0 : -16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .navigationTitle(navigator.selectedTab.displayName)
                .toolbar {
                    ToolbarItemGroup(placement: .navigation) {
                        ControlGroup {
                            Button(action: goBack) {
                                Image(systemName: "chevron.left")
                            }
                            .disabled(historyIndex <= 0)

                            Button(action: goForward) {
                                Image(systemName: "chevron.right")
                            }
                            .disabled(historyIndex >= navigationHistory.count - 1)
                        }
                        .controlGroupStyle(.navigation)
                    }
                }
        }
        .navigationSplitViewStyle(.balanced)
        .background(
            WindowConfigurator { window in
                window.titlebarSeparatorStyle = .none
            }
        )
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

    @ViewBuilder
    private var securityLockIcon: some View {
        if #available(macOS 15.0, *) {
            Image(systemName: isSecurityUnlocked ? "lock.open.fill" : "lock.fill")
                .contentTransition(.symbolEffect(.replace.magic(fallback: .downUp.byLayer)))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isSecurityUnlocked ? .blue : .secondary)
        } else {
            Image(systemName: isSecurityUnlocked ? "lock.open.fill" : "lock.fill")
                .contentTransition(.symbolEffect(.replace.downUp.byLayer))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isSecurityUnlocked ? .blue : .secondary)
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
            LogsSettingsTab(isMock: isMock)
        }
    }
}

#Preview {
    SettingsView(isMock: true)
}
