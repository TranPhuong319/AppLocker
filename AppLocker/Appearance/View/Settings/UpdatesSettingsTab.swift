//
//  UpdatesSettingsTab.swift
//  AppLocker
//
//  Created by Doe Phương on 18/8/25.
//

import SwiftUI
import Sparkle

struct UpdatesSettingsTab: View {
    @Binding var hasAvailableUpdate: Bool
    @Binding var availableUpdateVersion: String
    let isMock: Bool

    @AppStorage("automaticallyChecksForUpdates") private var autoCheck: Bool = true
    @AppStorage("automaticallyDownloadsUpdates") private var autoDownload: Bool = false
    @AppStorage("updateChannel") private var selectedChannelRaw: String = UpdateChannel.stable.rawValue

    private var selectedChannel: UpdateChannel {
        UpdateChannel(rawValue: selectedChannelRaw) ?? .stable
    }

    var body: some View {
        Form {
            Section(header: Text("Software Updates")) {
                currentVersionRow

                Toggle("Automatically check for updates", isOn: $autoCheck)
                    .onChange(of: autoCheck) { newValue in
                        if !newValue {
                            autoDownload = false
                        }
                        if !isMock {
                            let updater = AppUpdater.shared.updaterController.updater
                            updater.automaticallyChecksForUpdates = newValue
                            if !newValue {
                                updater.automaticallyDownloadsUpdates = false
                            }
                        }
                    }

                Toggle("Automatically download new updates", isOn: $autoDownload)
                    .disabled(!autoCheck)
                    .onChange(of: autoDownload) { newValue in
                        if !isMock {
                            let updater = AppUpdater.shared.updaterController.updater
                            updater.automaticallyDownloadsUpdates = newValue
                        }
                    }

                Picker("Update Channel", selection: $selectedChannelRaw) {
                    ForEach(UpdateChannel.allCases) { channel in
                        Text(channel.displayName).tag(channel.rawValue)
                    }
                }

                Text(selectedChannel.description)
                    .font(.caption)
                    .foregroundColor(.secondary)

                Button(action: checkForUpdates, label: {
                    Label("Check for Updates Now", systemImage: "arrow.trianglehead.2.clockwise.rotate.90")
                })
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var currentVersionRow: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Current Version")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)

                Text("Version \(Bundle.main.fullVersion)")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer()

            if hasAvailableUpdate {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundColor(.blue)
                    Text("Version \(availableUpdateVersion) available")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.blue)
                }
            } else {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Up to Date")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.green)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func checkForUpdates() {
        guard !isMock else { return }
        (NSApp.delegate as? AppDelegate)?.checkUpdate()
    }
}

#Preview {
    UpdatesSettingsTab(
        hasAvailableUpdate: .constant(false),
        availableUpdateVersion: .constant(""),
        isMock: true
    )
}
