//
//  UpdatesSettingsTab.swift
//  AppLocker
//
//  Created by Doe Phương on 18/8/25.
//

import SwiftUI

struct UpdatesSettingsTab: View {
    let isMock: Bool

    @State private var hasAvailableUpdate: Bool = false
    @State private var availableUpdateVersion: String = ""
    @AppStorage("automaticallyChecksForUpdates") private var autoCheck: Bool = true
    @AppStorage("automaticallyDownloadsUpdates") private var autoDownload: Bool = false
    @AppStorage("updateChannel") private var selectedChannelRaw: String = UpdateChannel.stable.rawValue

    init(isMock: Bool = false) {
        self.isMock = isMock
    }

    private var selectedChannel: UpdateChannel {
        UpdateChannel(rawValue: selectedChannelRaw) ?? .stable
    }

    var body: some View {
        Form {
            Section(header: Text("Software Updates")) {
                currentVersionRow

                Toggle("Automatically check for updates", isOn: $autoCheck)
                    .onChange(of: autoCheck) { _, newValue in
                        if !newValue {
                            autoDownload = false
                        }
                        if !isMock {
                            AppUpdater.shared.automaticallyChecksForUpdates = newValue
                            if !newValue {
                                AppUpdater.shared.automaticallyDownloadsUpdates = false
                            }
                        }
                    }

                Toggle("Automatically download new updates", isOn: $autoDownload)
                    .disabled(!autoCheck)
                    .onChange(of: autoDownload) { _, newValue in
                        if !isMock {
                            AppUpdater.shared.automaticallyDownloadsUpdates = newValue
                        }
                    }

                Text("Automatically download new updates in the background when available.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("Update Channel", selection: $selectedChannelRaw) {
                    ForEach(UpdateChannel.allCases) { channel in
                        Text(channel.displayName).tag(channel.rawValue)
                    }
                }

                Text(selectedChannel.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button(action: checkForUpdates, label: {
                    Label("Check for Updates Now", systemImage: "arrow.trianglehead.2.clockwise.rotate.90")
                })
            }
        }
        .formStyle(.grouped)
        .task {
            updateSparkleStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: .appLockerPendingUpdateDidChange)) { _ in
            updateSparkleStatus()
        }
    }

    @ViewBuilder
    private var currentVersionRow: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Current Version")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)

                Text("Version \(Bundle.main.fullVersion)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 4) {
                Image(systemName: hasAvailableUpdate ? "arrow.down.circle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(hasAvailableUpdate ? .blue : .green)
                Text(hasAvailableUpdate ? "Version \(availableUpdateVersion) available" : "Up to Date")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(hasAvailableUpdate ? .blue : .green)
            }
        }
        .padding(.vertical, 4)
    }

    private func updateSparkleStatus() {
        guard !isMock else { return }
        hasAvailableUpdate = AppUpdater.shared.hasAvailableUpdate
        availableUpdateVersion = AppUpdater.shared.availableUpdateVersion ?? ""
    }

    private func checkForUpdates() {
        guard !isMock else { return }
        AppUpdater.shared.checkForUpdates()
    }
}

#Preview {
    UpdatesSettingsTab(isMock: true)
}
