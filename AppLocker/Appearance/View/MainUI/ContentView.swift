//
//  ContentView.swift
//  AppLocker
//
//  Copyright © 2025 TranPhuong319. All rights reserved.
//

import SwiftUI

struct ContentView: View {
    @ObservedObject var appState = AppState.shared
    @FocusState var isSearchFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            headerView

            if appState.lockedAppObjects.isEmpty {
                emptyStateView
            } else {
                mainListView
            }
        }
        .padding(12)
        .contentShape(Rectangle())
        .onTapGesture { isSearchFocused = false }

        .sheet(isPresented: $appState.showingAddApp) {
            AddAppSheet(appState: appState, unfocus: unfocus)
        }
        .sheet(isPresented: $appState.showingDeleteQueue) {
            DeleteQueueSheet(appState: appState)
        }
        .sheet(isPresented: $appState.showingLockingPopup) {
            LockingPopupSheet(message: appState.lockingMessage)
        }
    }

    // MARK: - Subviews / Thành phần con
    @ViewBuilder
    private var headerView: some View {
        HStack {
            Text("Locked application".localized).font(.headline)
            Spacer()
            Button { appState.openAddApp() } label: { Image(systemName: "plus") }
            .help("Add application to lock".localized)
            .disabled(appState.isDisabled)
        }
        .padding(.horizontal, 8)
    }

    @ViewBuilder
    private var emptyStateView: some View {
        Text("There is no locked application.".localized)
            .foregroundColor(.secondary)
            .font(.title3)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    @ViewBuilder
    private var mainListView: some View {
        VStack(spacing: 9) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .padding(.leading, 4)

                TextField("Search apps...".localized, text: $appState.searchTextLockApps)
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
            .padding(.horizontal, 8)

            ZStack(alignment: .bottom) {
                ScrollView {
                    LazyVStack(alignment: .center, spacing: 6) {
                        let apps = appState.filteredLockedApps
                        let userApps = apps.filter { $0.source == .user }
                        let systemApps = apps.filter { $0.source == .system }

                        if !userApps.isEmpty {
                            SectionHeader(title: "Applications".localized)
                            ForEach(userApps, id: \.path) {
                                LockedAppRow(
                                    app: $0,
                                    appState: appState,
                                    unfocus: unfocus
                                )
                            }
                        }

                        if !systemApps.isEmpty {
                            SectionHeader(title: "System Applications".localized)
                            ForEach(systemApps, id: \.path) {
                                LockedAppRow(
                                    app: $0,
                                    appState: appState,
                                    unfocus: unfocus
                                )
                            }
                        }

                        if userApps.isEmpty && systemApps.isEmpty && !apps.isEmpty {
                            ForEach(apps) {
                                LockedAppRow(
                                    app: $0,
                                    appState: appState,
                                    unfocus: unfocus
                                )
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    .padding(.bottom, appState.deleteQueue.isEmpty ? 0 : 60)
                }
                .scrollIndicators(.hidden)
                .background(Color.white.opacity(0.000001).onTapGesture { isSearchFocused = false })
                .clipShape(RoundedRectangle(cornerRadius: 12))

                if !appState.deleteQueue.isEmpty {
                    deleteQueueNotificationBar
                }
            }
            .animation(.spring(), value: appState.deleteQueue.isEmpty)
        }
    }

    private func unfocus() {
        isSearchFocused = false
        DispatchQueue.main.async {
            NSApp.keyWindow?.makeFirstResponder(nil)
        }
    }

    @ViewBuilder
    private var deleteQueueNotificationBar: some View {
        Button { appState.showingDeleteQueue = true } label: {
            HStack {
                Image(systemName: "tray.full")
                Text("Waiting to unlock %d application(s)...".localized(with: appState.deleteQueue.count)).bold()
            }
            .frame(maxWidth: .infinity, maxHeight: 35)
            .background(Color.red.opacity(0.8))
            .foregroundColor(.white)
            .cornerRadius(8)
            .shadow(radius: 4)
        }
        .buttonStyle(PlainButtonStyle()).padding(.horizontal, 16).padding(.bottom, 12)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

#Preview {
    ContentView()
        .frame(width: CGFloat(AppState.shared.setWidth),
               height: CGFloat(AppState.shared.setHeight))
}
