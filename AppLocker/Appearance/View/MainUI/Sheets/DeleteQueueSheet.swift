//
//  DeleteQueueSheet.swift
//  AppLocker
//
//  Created by Doe Phương on 28/12/25.
//

import SwiftUI

struct DeleteQueueSheet: View {
    @ObservedObject var appState: AppState
    @State private var sharedWidth: CGFloat = 0

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
                                DeleteQueueRow(app: app, appState: appState)
                            }
                        }
                        
                        let systemApps = appsInQueue.filter { $0.source == .system }
                        if !systemApps.isEmpty {
                            SectionHeader(title: "System Applications")
                            ForEach(systemApps, id: \.path) { app in
                                DeleteQueueRow(app: app, appState: appState)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
                .scrollIndicators(.hidden)
                .padding(.horizontal)
                .frame(maxWidth: .infinity)
                .frame(maxHeight: .infinity)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Delete all from the waiting list") {
                        appState.deleteAllFromWaitingList()
                    }
                    .controlSize(.large)
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Unlock") {
                        appState.unlockApp()
                    }
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.large)
                }
            }
        }
        .frame(minWidth: 350, minHeight: 370)
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
