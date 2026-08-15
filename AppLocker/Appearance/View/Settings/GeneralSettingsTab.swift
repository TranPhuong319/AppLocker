//
//  GeneralSettingsTab.swift
//  AppLocker
//
//  Created by Doe Phương on 18/8/25.
//

import SwiftUI

struct GeneralSettingsTab: View {
    let isMock: Bool

    @State private var isAgentActive: Bool = true
    @AppStorage("showBlockedNotifications") private var showNotifications: Bool = true

    init(isMock: Bool = false) {
        self.isMock = isMock
    }

    var body: some View {
        Form {
            Section(header: Text("Background Security Service")) {
                HStack {
                    Label(
                        "Background Agent Status",
                        systemImage: isAgentActive ? "shield.checkered" : "exclamationmark.shield"
                    )
                    Spacer()
                    if isAgentActive {
                        Text("Active")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.green)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(Color.green.opacity(0.15))
                            )
                    } else {
                        Text("Inactive")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.red)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(Color.red.opacity(0.15))
                            )
                    }
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
        .onAppear {
            checkAgentStatus()
        }
    }

    private func checkAgentStatus() {
        guard !isMock else { return }
        if let appDelegate = NSApp.delegate as? AppDelegate {
            isAgentActive = appDelegate.checkAgentStatus()
        }
    }

    private func repairAgentService() {
        guard !isMock else { return }
        if let appDelegate = NSApp.delegate as? AppDelegate {
            isAgentActive = appDelegate.repairAgentService()
        }
    }
}

#Preview {
    GeneralSettingsTab(isMock: true)
}
