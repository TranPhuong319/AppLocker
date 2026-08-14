//
//  DeleteQueueSheet.swift
//  AppLocker
//
//  Created by Doe Phương on 28/12/25.
//

import SwiftUI

struct DeleteQueueSheet: View {
    @ObservedObject var appState: AppState
    @State private var maxButtonWidth: CGFloat?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                Text("Application is waiting to be deleted")
                    .font(.headline)
                    .padding([.horizontal, .top])
                    .padding(.bottom)

                Divider()

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
                    .padding(.vertical, 8)
                }
                .scrollIndicators(.hidden)
                .padding(.horizontal)
                Divider()

                HStack(spacing: 12) {
                    Spacer()

                    Button(
                        action: {
                            appState.deleteAllFromWaitingList()
                        },
                        label: {
                            Text(String(localized: "Cancel"))
                                .font(.system(size: 13, weight: .medium))
                                .lineLimit(1)
                                .padding(.horizontal, 8)
                                .background(
                                    GeometryReader { geo in
                                        Color.clear.preference(key: EqualWidthKey.self, value: geo.size.width)
                                    }
                                )
                                .frame(width: maxButtonWidth)
                        }
                    )
                    .buttonStyle(.bordered)
                    .controlSize(.large)

                    Button(
                        action: {
                            appState.unlockApp()
                        },
                        label: {
                            Text(String(localized: "Unlock"))
                                .font(.system(size: 13, weight: .semibold))
                                .lineLimit(1)
                                .padding(.horizontal, 8)
                                .background(
                                    GeometryReader { geo in
                                        Color.clear.preference(key: EqualWidthKey.self, value: geo.size.width)
                                    }
                                )
                                .frame(width: maxButtonWidth)
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
                .padding(.vertical, 12)
            }
        }
        .frame(
            minWidth: WindowLayout.deleteQueueMinSize.width,
            minHeight: WindowLayout.deleteQueueMinSize.height
        )
        .onAppear {
            DispatchQueue.main.async {
                appState.activeTouchBar = .deleteQueuePopup
            }
        }
        .onDisappear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                appState.activeTouchBar = .mainWindow
                appState.searchTextLockApps = ""
            }
        }
    }
}

private struct EqualWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
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
