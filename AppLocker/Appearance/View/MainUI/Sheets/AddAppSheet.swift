//
//  AddAppSheet.swift
//  AppLocker
//
//  Created by Doe Phương on 28/12/25.
//

import SwiftUI

struct AddAppSheet: View {
    @ObservedObject var appState: AppState
    @FocusState var isSearchFocused: Bool
    let unfocus: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                        .padding(.leading, 4)

                    TextField("Search apps...".localized, text: $appState.searchTextUnlockaleApps)
                        .textFieldStyle(.plain)
                        .focused($isSearchFocused)
                        .onSubmit { unfocus() }
                }
                .padding(7)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.2))
                )
                .padding(.horizontal)
                .padding(.vertical)
                Divider()

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        let userApps = appState.filteredUnlockableApps.filter { $0.source == .user }
                        if !userApps.isEmpty {
                            SectionHeader(title: "Applications".localized)
                            ForEach(userApps, id: \.path) { app in
                                AppRow(app: app, appState: appState, unfocus: unfocus)
                            }
                        }

                        let systemApps = appState.filteredUnlockableApps.filter { $0.source == .system }
                        if !systemApps.isEmpty {
                            SectionHeader(title: "System Applications".localized)
                                .padding(.top, 10)
                            ForEach(systemApps, id: \.path) { app in
                                AppRow(app: app, appState: appState, unfocus: unfocus)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
                .scrollIndicators(.hidden)
                .padding(.horizontal)
                .frame(maxWidth: .infinity)
                .frame(maxHeight: 420)
            }
            .contentShape(Rectangle())
            .onTapGesture { unfocus() }
            .navigationTitle("Select the application to lock".localized)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: {
                        appState.lockButton()
                    }) {
                        Text("Lock (%d)".localized(with: appState.selectedToLock.count))
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(appState.selectedToLock.isEmpty || appState.isLocking)
                }

                ToolbarItem(placement: .cancellationAction) {
                    Button("Close".localized) {
                        appState.closeAddPopup()
                    }
                }

                ToolbarItem(placement: .automatic) {
                    Button("Others…") {
                        appState.addOthersApp()
                    }
                }
            }
        }
        .frame(minWidth: 400, minHeight: 500)
        .onTapGesture { unfocus() }
        .onAppear {
            unfocus()
            appState.manager.reloadAllApps()

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                NSApp.keyWindow?.makeFirstResponder(nil)

                let tb = TouchBarManager.shared.makeTouchBar(for: .addAppPopup)
                NSApp.keyWindow?.touchBar = tb
            }
        }

        .onDisappear {
            DispatchQueue.main.async {
                appState.searchTextUnlockaleApps = ""
                if let mainWindow = NSApp.windows.first(where: { $0.isVisible && !$0.isSheet }) {
                    TouchBarManager.shared.apply(to: mainWindow, type: .mainWindow)
                }
            }
        }
    }
}
