//
//  DeleteQueueSheet.swift
//  AppLocker
//
//  Created by Doe Phương on 28/12/25.
//

import SwiftUI

struct DeleteQueueSheet: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Application is waiting to be deleted".localized)
                .font(.headline)
                .padding([.horizontal, .top])
                .padding(.bottom, 0)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    let appsInQueue = appState.lockedAppObjects.filter { appState.deleteQueue.contains($0.path) }

                    let userApps = appsInQueue.filter { $0.source == .user }
                    if !userApps.isEmpty {
                        SectionHeader(title: "Applications".localized)
                        ForEach(userApps, id: \.path) { app in
                            DeleteQueueRow(app: app, appState: appState)
                        }
                    }

                    let systemApps = appsInQueue.filter { $0.source == .system }
                    if !systemApps.isEmpty {
                        SectionHeader(title: "System Applications".localized)
                        ForEach(systemApps, id: \.path) { app in
                            DeleteQueueRow(app: app, appState: appState)
                        }
                    }
                }
                .padding(.vertical, 8)
            }
            .scrollIndicators(.hidden)
            .frame(maxHeight: 270)
            .padding(.horizontal)

            Divider()

            HStack {
                Spacer()
                Button("Delete all from the waiting list".localized) {
                    appState.deleteAllFromWaitingList()
                }
                .keyboardShortcut(.cancelAction)
                Button("Unlock".localized) {
                    appState.unlockApp()
                }
                .accentColor(.accentColor)
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(minWidth: 350, minHeight: 370)
        .onAppear {
            DispatchQueue.main.async {
                let touchBar = TouchBarManager.shared.makeTouchBar(for: .deleteQueuePopup)
                NSApp.keyWindow?.touchBar = touchBar
            }
        }
        .onDisappear {
            DispatchQueue.main.async {
                if let mainWindow = NSApp.windows.first(where: { $0.isVisible && !$0.isSheet }) {
                    TouchBarManager.shared.apply(to: mainWindow, type: .mainWindow)
                }
                appState.searchTextLockApps = ""
            }
        }
    }
}
