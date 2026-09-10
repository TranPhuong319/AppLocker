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
    var selectedTab: SettingsTab

    init(selectedTab: SettingsTab = .general) {
        self.selectedTab = selectedTab
    }
}

// MARK: - Sidebar Collapse Preventer

struct SidebarCollapsePreventer: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        guard ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" else {
            return view
        }
        DispatchQueue.main.async {
            guard let splitView = view.enclosingSplitView,
                  let splitViewController = splitView.delegate as? NSSplitViewController,
                  let sidebarItem = splitViewController.splitViewItems.first else {
                return
            }
            sidebarItem.canCollapse = false
            sidebarItem.canCollapseFromWindowResize = false
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private extension NSView {
    var enclosingSplitView: NSSplitView? {
        var current = superview
        while let view = current {
            if let split = view as? NSSplitView {
                return split
            }
            current = view.superview
        }
        return nil
    }
}

private extension View {
    func preventSidebarCollapse() -> some View {
        background(SidebarCollapsePreventer())
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

    init(
        selectedTab: SettingsTab,
        isMock: Bool = false
    ) {
        self.navigator = SettingsNavigator(selectedTab: selectedTab)
        self.isMock = isMock
    }

    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            List(SettingsTab.allCases, id: \.self, selection: $navigator.selectedTab) { tab in
                HStack(spacing: 8) {
                    Label {
                        Text(tab.displayName)
                            .font(.system(size: 13, weight: .medium))
                    } icon: {
                        Image(systemName: tab.iconName)
                            .foregroundStyle(.blue)
                    }

                    if tab == .security {
                        Spacer()
                        Button(action: toggleSecurityLock) {
                            Image(systemName: isSecurityUnlocked ? "lock.open.fill" : "lock.fill")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(isSecurityUnlocked ? .blue : .secondary)
                        }
                        .buttonStyle(.plain)
                        .help(isSecurityUnlocked ? "Lock security settings" : "Unlock security settings")
                    }
                }
                .tag(tab)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 150, ideal: 150, max: 150)
            .preventSidebarCollapse()
        } detail: {
            detailContent(for: navigator.selectedTab)
                .padding(.top, -16)
                .frame(minWidth: 440, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(.windowBackground)
                .navigationTitle(navigator.selectedTab.displayName)
                .toolbar {
                    ToolbarItem(placement: .navigation) {
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
        .frame(minWidth: 640, minHeight: 440)
        .onChange(of: navigator.selectedTab) { _, newTab in
            handleTabChange(to: newTab)
        }
    }

    private func toggleSecurityLock() {
        if isSecurityUnlocked {
            withAnimation(.snappy(duration: 0.3)) {
                isSecurityUnlocked = false
            }
        } else if navigator.selectedTab != .security {
            navigator.selectedTab = .security
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
    private func detailContent(for tab: SettingsTab) -> some View {
        switch tab {
        case .general:
            GeneralSettingsTab(isMock: isMock)
        case .security:
            SecuritySettingsTab(isUnlocked: $isSecurityUnlocked, isMock: isMock)
        case .updates:
            UpdatesSettingsTab(isMock: isMock)
        case .appearance:
            AppearanceSettingsTab(isMock: isMock)
        }
    }
}

#Preview {
    SettingsView(isMock: true)
}
