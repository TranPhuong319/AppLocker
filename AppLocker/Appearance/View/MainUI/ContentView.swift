//
//  ContentView.swift
//  AppLocker
//
//  Created by Doe Phương on 24/7/25.
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
            Text("Locked application").font(.headline)
            Spacer()
            Button { appState.openAddApp() } label: { Image(systemName: "plus") }
            .help("Add application to lock")
        }
        .padding(.horizontal, 8)
    }

    @ViewBuilder
    private var emptyStateView: some View {
        Text("There is no locked application.")
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
                    .padding(.leading, 8)

                TextField("Search apps...", text: $appState.searchTextLockApps)
                    .textFieldStyle(.plain)
                    .focused($isSearchFocused)
                    .onSubmit { unfocus() }
            }
            .padding(7)
            .background {
                Capsule()
                    .fill(Color(NSColor.controlBackgroundColor).opacity(0.5))
            }
            .overlay(
                Capsule()
                    .stroke(Color.secondary.opacity(0.15))
            )
            .padding(.horizontal, 8)

            ZStack(alignment: .bottom) {
                ScrollView {
                    LazyVStack(alignment: .center, spacing: 6) {
                        let apps = appState.filteredLockedApps
                        let userApps = apps.filter { $0.source == .user }
                        let systemApps = apps.filter { $0.source == .system }

                        if !userApps.isEmpty {
                            SectionHeader(title: "Applications")
                            ForEach(userApps, id: \.path) {
                                LockedAppRow(
                                    app: $0,
                                    appState: appState,
                                    unfocus: unfocus
                                )
                            }
                        }

                        if !systemApps.isEmpty {
                            SectionHeader(title: "System Applications")
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
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.red.opacity(0.15))
                        .frame(width: 26, height: 26)
                    Image(systemName: "tray.full.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.red)
                }

                Text("Waiting to unlock \(appState.deleteQueue.count) application(s)...")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary.opacity(0.6))
            }
            .padding(.horizontal, 8)
            .padding(.leading, 4)
            .frame(maxWidth: .infinity, maxHeight: 42)
            .contentShape(Capsule())
            .liquidGlass(in: Capsule()) {
                ZStack {
                    Capsule()
                        .fill(.ultraThinMaterial)
                    Capsule()
                        .stroke(Color.secondary.opacity(0.15), lineWidth: 0.5)
                }
            }
            .shadow(color: .black.opacity(0.12), radius: 10, x: 0, y: 5)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.bottom, 20)
        .transition(.asymmetric(
            insertion: .move(edge: .bottom).combined(with: .opacity),
            removal: .move(edge: .bottom).combined(with: .opacity)
        ))
    }
}


#Preview {
    ContentView()
        .frame(width: WindowLayout.Main.size.width,
               height: WindowLayout.Main.size.height)
        .environmentObject(AppState.shared)
}
