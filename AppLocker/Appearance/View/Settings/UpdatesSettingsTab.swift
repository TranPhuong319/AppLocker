//
//  UpdatesSettingsTab.swift
//  AppLocker
//
//  Created by Doe Phương on 18/8/25.
//

import SwiftUI
import Sparkle

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
        .onAppear {
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
                    .foregroundColor(.primary)

                Text("Version \(Bundle.main.fullVersion)")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer()

            HStack(spacing: 4) {
                Image(systemName: hasAvailableUpdate ? "arrow.down.circle.fill" : "checkmark.circle.fill")
                    .foregroundColor(hasAvailableUpdate ? .blue : .green)
                Text(hasAvailableUpdate ? "Version \(availableUpdateVersion) available" : "Up to Date")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(hasAvailableUpdate ? .blue : .green)
            }
        }
        .padding(.vertical, 4)
    }

    private func updateSparkleStatus() {
        guard !isMock, let appDelegate = NSApp.delegate as? AppDelegate else { return }
        if let update = appDelegate.pendingUpdate {
            hasAvailableUpdate = true
            let displayVer = update.displayVersionString
            let buildVer = update.versionString
            if displayVer != buildVer {
                availableUpdateVersion = "\(displayVer) (\(buildVer))"
            } else {
                availableUpdateVersion = displayVer
            }
        } else {
            hasAvailableUpdate = false
            availableUpdateVersion = ""
        }
    }

    private func checkForUpdates() {
        guard !isMock else { return }
        (NSApp.delegate as? AppDelegate)?.checkUpdate()
    }
}

#Preview {
    UpdatesSettingsTab(isMock: true)
}
