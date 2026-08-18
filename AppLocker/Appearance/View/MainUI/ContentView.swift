//
//  ContentView.swift
//  AppLocker
//
//  Created by Doe Phương on 24/7/25.
//

import SwiftUI

struct ContentView: View {
    @ObservedObject var appState: AppState
    @FocusState var isSearchFocused: Bool

    @MainActor
    init(appState: AppState? = nil) {
        self.appState = appState ?? AppState.shared
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 8) {
                if appState.lockedAppObjects.isEmpty {
                    emptyStateView
                } else {
                    searchBarHeader
                    mainListView
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, 10)
            .background(
                VisualEffectView(material: .sidebar, blendingMode: .behindWindow)
                    .ignoresSafeArea()
            )
            .navigationTitle("Locked application")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        appState.openAddApp()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .help("Add application to lock")
                }
            }
        }
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
    private var searchBarHeader: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
                .padding(.leading, 8)

            TextField("Search apps...", text: $appState.searchTextLockApps)
                .textFieldStyle(.plain)
                .focused($isSearchFocused)
                .onSubmit { unfocus() }
                .onExitCommand { unfocus() }
        }
        .padding(7)
        .contentShape(Capsule())
        .onTapGesture { isSearchFocused = true }
        .liquidGlassCapsule()
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
        ZStack(alignment: .bottom) {
            ScrollView {
                LazyVStack(alignment: .center, spacing: 6) {
                    let apps = appState.filteredLockedApps
                    let userApps = apps.filter { $0.source == .user }
                    let systemApps = apps.filter { $0.source == .system }

                    if !userApps.isEmpty {
                        SectionHeader(title: "Applications")
                        ForEach(userApps, id: \.path) { app in
                            LockedAppButton(
                                app: app,
                                isDeleting: appState.deleteQueue.contains(app.path),
                                onDelete: { _ = appState.deleteQueue.insert(app.path) },
                                unfocus: unfocus
                            )
                        }
                    }

                    if !systemApps.isEmpty {
                        SectionHeader(title: "System Applications")
                        ForEach(systemApps, id: \.path) { app in
                            LockedAppButton(
                                app: app,
                                isDeleting: appState.deleteQueue.contains(app.path),
                                onDelete: { _ = appState.deleteQueue.insert(app.path) },
                                unfocus: unfocus
                            )
                        }
                    }
                }
                .padding(.vertical, 4)
                .padding(.bottom, appState.deleteQueue.isEmpty ? 0 : 60)
            }
            .scrollIndicators(.hidden)
            .background(Color.clear.contentShape(Rectangle()).onTapGesture { isSearchFocused = false })
            .clipped()

            if !appState.deleteQueue.isEmpty {
                deleteQueueNotificationBar
            }
        }
        .animation(.spring(), value: appState.deleteQueue.isEmpty)
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
            .liquidGlassCapsule()
            .shadow(color: .black.opacity(0.12), radius: 10, x: 0, y: 5)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .transition(.asymmetric(
            insertion: .move(edge: .bottom).combined(with: .opacity),
            removal: .move(edge: .bottom).combined(with: .opacity)
        ))
    }
}

#Preview("Empty State") {
    ContentView(appState: .preview(locked: []))
        .frame(width: WindowLayout.mainSize.width,
               height: WindowLayout.mainSize.height)
}

#Preview("User Apps Only") {
    ContentView(appState: .preview(locked: [.mockChrome, .mockVSCode]))
        .frame(width: WindowLayout.mainSize.width,
               height: WindowLayout.mainSize.height)
}

#Preview("System Apps Only") {
    ContentView(appState: .preview(locked: [.mockSafari, .mockFinder]))
        .frame(width: WindowLayout.mainSize.width,
               height: WindowLayout.mainSize.height)
}

#Preview("Both Types") {
    ContentView(appState: .preview(locked: InstalledApp.allMocks))
        .frame(width: WindowLayout.mainSize.width,
               height: WindowLayout.mainSize.height)
}
