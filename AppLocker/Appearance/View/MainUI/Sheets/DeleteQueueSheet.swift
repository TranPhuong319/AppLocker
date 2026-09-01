//
//  DeleteQueueSheet.swift
//  AppLocker
//
//  Created by Doe Phương on 28/12/25.
//

import SwiftUI

struct DeleteQueueSheet: View {
    var appState: AppState
    @State private var maxButtonWidth: CGFloat?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                topHeader

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        let appsInQueue = appState.lockedAppObjects.filter {
                            appState.deleteQueue.contains($0.path)
                        }

                        let userApps = appsInQueue.filter { $0.source == .user }
                        if !userApps.isEmpty {
                            SectionHeader(title: "Applications")
                            ForEach(userApps, id: \.path) { app in
                                DeleteAppButton(app: app, appState: appState)
                            }
                        }

                        let systemApps = appsInQueue.filter { $0.source == .system }
                        if !systemApps.isEmpty {
                            SectionHeader(title: "System Applications")
                            ForEach(systemApps, id: \.path) { app in
                                DeleteAppButton(app: app, appState: appState)
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }
                .scrollIndicators(.hidden)
                .clipped()

                bottomActionBar
            }
            .background(
                VisualEffectView(material: .sidebar, blendingMode: .behindWindow)
                    .ignoresSafeArea()
            )
        }
        .frame(
            minWidth: WindowLayout.deleteQueueMinSize.width,
            minHeight: WindowLayout.deleteQueueMinSize.height
        )
        .task {
            appState.activeTouchBar = .deleteQueuePopup
        }
        .onDisappear {
            appState.activeTouchBar = .mainWindow
            appState.searchTextLockApps = ""
        }
    }

    @ViewBuilder
    private var topHeader: some View {
        HStack {
            Text("Application is waiting to be deleted")
                .font(.headline)
            Spacer()
        }
        .padding(.horizontal)
        .padding(.top, 16)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var bottomActionBar: some View {
        HStack(spacing: 12) {
            Spacer()

            Button(
                action: {
                    appState.clearDeleteQueue()
                },
                label: {
                    Text(String(localized: "Cancel"))
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.horizontal, 10)
                        .background(
                            GeometryReader { geo in
                                Color.clear.preference(key: EqualWidthKey.self, value: geo.size.width)
                            }
                        )
                        .frame(minWidth: maxButtonWidth)
                }
            )
            .buttonStyle(.bordered)
            .controlSize(.large)

            Button(
                action: {
                    appState.unlockQueuedApps()
                },
                label: {
                    Text(String(localized: "Unlock"))
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.horizontal, 10)
                        .background(
                            GeometryReader { geo in
                                Color.clear.preference(key: EqualWidthKey.self, value: geo.size.width)
                            }
                        )
                        .frame(minWidth: maxButtonWidth)
                }
            )
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .controlSize(.large)
        }
        .onPreferenceChange(EqualWidthKey.self) { width in
            if width > 0 {
                self.maxButtonWidth = width
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    DeleteQueueSheet(
        appState: .preview(
            locked: [.mockChrome, .mockSafari],
            deleteQueue: [InstalledApp.mockChrome.path, InstalledApp.mockSafari.path]
        )
    )
}
