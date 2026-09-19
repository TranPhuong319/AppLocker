//
//  ContentView.swift
//  AppLocker
//
//  Created by Doe Phương on 24/7/25.
//

import SwiftUI

struct ContentView: View {
    @Bindable var appState: AppState

    @MainActor
    init(appState: AppState? = nil) {
        self.appState = appState ?? AppState.shared
    }

    var body: some View {
        NavigationStack {
            contentView
                .navigationTitle("Locked application")
                .searchable(
                    text: $appState.searchTextLockApps,
                    isPresented: $appState.isSearchPresented,
                    prompt: "Search apps..."
                )
                .toolbar {
                    if !appState.confirmedMissingApps.isEmpty {
                        ToolbarItem(placement: .primaryAction) {
                            missingAppsWarningButton
                        }
                    }

                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            appState.openAddApp()
                        } label: {
                            Label("Add Application", systemImage: "plus")
                        }
                        .labelStyle(.iconOnly)
                        .help("Add application to lock")
                    }
                }
        }
        .background(
            VisualEffectView(material: .underWindowBackground, blendingMode: .behindWindow)
                .ignoresSafeArea()
        )
        .sheet(isPresented: $appState.showingAddApp) {
            AddAppSheet(appState: appState, unfocus: unfocus)
        }
        .sheet(isPresented: $appState.showingDeleteQueue) {
            DeleteQueueSheet(appState: appState)
        }
        .sheet(isPresented: $appState.showingMissingAppsSheet) {
            MissingAppsSheet(appState: appState)
        }
        .sheet(isPresented: $appState.showingLockingPopup) {
            LockingPopupSheet(message: appState.lockingMessage)
        }
    }

    func unfocus() {
        NSApp.keyWindow?.makeFirstResponder(nil)
    }
}

// MARK: - Subviews
private extension ContentView {
    @ViewBuilder
    var contentView: some View {
        if appState.lockedAppObjects.isEmpty {
            emptyStateView
        } else {
            mainListView
        }
    }

    @ViewBuilder
    var missingAppsWarningButton: some View {
        Button {
            appState.openMissingApps()
        } label: {
            Label {
                Text("Review missing applications (\(appState.confirmedMissingApps.count))")
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .symbolEffect(.bounce.byLayer, value: appState.confirmedMissingApps.count)
            }
        }
        .labelStyle(.iconOnly)
        .help(String(localized: "Review missing applications"))
        .accessibilityLabel(String(localized: "Review missing applications"))
    }

    @ViewBuilder
    var emptyStateView: some View {
        Text("There is no locked application.")
            .foregroundStyle(.secondary)
            .font(.title3)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .padding(.horizontal, 14)
    }

    @ViewBuilder
    var mainListView: some View {
        let apps = appState.filteredLockedApps
        let userApps = apps.filter { $0.source == .user }
        let systemApps = apps.filter { $0.source == .system }
        let missingPaths = Set(appState.confirmedMissingApps.map(\.path))

        ScrollView {
            LazyVStack(alignment: .center, spacing: 6) {
                appSection(titled: "Applications", for: userApps, missingPaths: missingPaths)
                appSection(titled: "System Applications", for: systemApps, missingPaths: missingPaths)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
        }
        .scrollIndicators(.hidden)
        .background(Color.clear.contentShape(Rectangle()).onTapGesture { unfocus() })
        .safeAreaPadding(.bottom, appState.deleteQueue.isEmpty ? 10 : 62)
        .mask(scrollEdgeDissolveMask)
        .overlay(alignment: .bottom) {
            if !appState.deleteQueue.isEmpty {
                deleteQueueNotificationBar
            }
        }
        .animation(.spring(), value: appState.deleteQueue.isEmpty)
    }

    @ViewBuilder
    func appSection(
        titled title: LocalizedStringKey,
        for apps: [InstalledApp],
        missingPaths: Set<String>
    ) -> some View {
        if !apps.isEmpty {
            SectionHeader(title)
            ForEach(apps, id: \.path) { app in
                LockedAppRow(
                    for: app,
                    isDeleting: appState.deleteQueue.contains(app.path),
                    isMissing: missingPaths.contains(app.path),
                    onDelete: { _ = appState.deleteQueue.insert(app.path) },
                    onUnfocus: unfocus
                )
            }
        }
    }

    var scrollEdgeDissolveMask: some View {
        VStack(spacing: 0) {
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0), location: 0),
                    .init(color: .black, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 20)

            Rectangle()

            LinearGradient(
                stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black.opacity(0), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 16)
        }
    }

    @ViewBuilder
    var deleteQueueNotificationBar: some View {
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
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.25), value: appState.deleteQueue.count)

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
        .contentShape(Capsule())
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
