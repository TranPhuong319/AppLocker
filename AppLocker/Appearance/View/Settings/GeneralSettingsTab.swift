//
//  GeneralSettingsTab.swift
//  AppLocker
//
//  Created by Doe Phương on 18/8/25.
//

import SwiftUI

struct GeneralSettingsTab: View {
    @Binding var isAgentActive: Bool
    let isMock: Bool

    @AppStorage("showBlockedNotifications") private var showNotifications: Bool = true

    var body: some View {
        Form {
            Section(header: Text("Background Security Service")) {
                HStack {
                    Label(
                        "Background Agent Status",
                        systemImage: isAgentActive ? "shield.checkered" : "exclamationmark.shield"
                    )
                    Spacer()
                    Group {
                        if isAgentActive {
                            #if DEBUG
                            Text("Active") + Text(" - Debug")
                            #else
                            Text("Active")
                            #endif
                        } else {
                            #if DEBUG
                            Text("Inactive") + Text(" - Debug")
                            #else
                            Text("Inactive")
                            #endif
                        }
                    }
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(isAgentActive ? .green : .red)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill((isAgentActive ? Color.green : Color.red).opacity(0.15))
                    )
                }

                #if DEBUG
                Toggle("Simulate Agent Active (Debug)", isOn: $isAgentActive)
                #endif

                if !isAgentActive {
                    Button(action: repairAgentService, label: {
                        Label("Repair Agent Service", systemImage: "wrench.and.screwdriver")
                    })
                    .help("Re-register launchctl agent service")
                }
            }

            Section(header: Text("Notifications")) {
                Toggle("Show notifications when an app is blocked", isOn: $showNotifications)
            }
        }
        .formStyle(.grouped)
    }

    private func repairAgentService() {
        guard !isMock else { return }
        if let appDelegate = NSApp.delegate as? AppDelegate {
            isAgentActive = appDelegate.repairAgentService()
        }
    }
}

#Preview {
    GeneralSettingsTab(isAgentActive: .constant(true), isMock: true)
}
