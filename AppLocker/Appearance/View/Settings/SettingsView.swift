//
//  SettingsView.swift
//  AppLocker
//
//  Created by Doe Phương on 18/8/25.
//

import SwiftUI

struct SettingsView: View {
    @State private var selectedTab: SettingsTab = .general
    @State private var navigationHistory: [SettingsTab] = [.general]
    @State private var historyIndex: Int = 0
    @State private var isNavigatingHistory: Bool = false
    private var isMock: Bool

    init(
        selectedTab: SettingsTab = .general,
        isMock: Bool = false
    ) {
        _selectedTab = State(initialValue: selectedTab)
        _navigationHistory = State(initialValue: [selectedTab])
        self.isMock = isMock
    }

    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            List(SettingsTab.allCases, id: \.self, selection: $selectedTab) { tab in
                Label {
                    Text(tab.displayName)
                        .font(.system(size: 13, weight: .medium))
                } icon: {
                    Image(systemName: tab.iconName)
                        .foregroundStyle(.blue)
                }
                .tag(tab)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 120, ideal: 150, max: 180)
        } detail: {
            detailContent(for: selectedTab)
                .padding(.top, -16)
                .frame(minWidth: 440, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .navigationTitle(selectedTab.displayName)
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
        .onChange(of: selectedTab) { _, newTab in
            handleTabChange(to: newTab)
        }
    }

    private func handleTabChange(to newTab: SettingsTab) {
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
        selectedTab = navigationHistory[historyIndex]
    }

    private func goForward() {
        guard historyIndex < navigationHistory.count - 1 else { return }
        isNavigatingHistory = true
        historyIndex += 1
        selectedTab = navigationHistory[historyIndex]
    }

    @ViewBuilder
    private func detailContent(for tab: SettingsTab) -> some View {
        switch tab {
        case .general:
            GeneralSettingsTab(isMock: isMock)
        case .security:
            SecuritySettingsTab(isMock: isMock)
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
