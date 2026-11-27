//
//  UpdatesSettingsTab.swift
//  AppLocker
//
//  Created by Doe Phương on 18/8/25.
//

import SwiftUI

struct UpdatesSettingsTab: View {
    let isMock: Bool

    @State private var hasAvailableUpdate: Bool
    @State private var availableUpdateVersion: String
    @State private var autoCheck: Bool
    @State private var autoDownload: Bool
    @State private var isBetaUsingStableFallback: Bool
    @AppStorage("updateChannel") private var selectedChannelRaw: String = UpdateChannel.stable.rawValue

    init(isMock: Bool = false) {
        #if DEBUG
        let effectiveMock = isMock || PreviewEnvironment.isRunningInPreview
        #else
        let effectiveMock = isMock
        #endif
        self.isMock = effectiveMock

        if effectiveMock {
            _hasAvailableUpdate = State(initialValue: false)
            _availableUpdateVersion = State(initialValue: "")
            _autoCheck = State(initialValue: true)
            _autoDownload = State(initialValue: false)
            _isBetaUsingStableFallback = State(initialValue: false)
        } else {
            let updater = AppUpdater.shared
            _hasAvailableUpdate = State(initialValue: updater.hasAvailableUpdate)
            _availableUpdateVersion = State(initialValue: updater.availableUpdateVersion ?? "")
            _autoCheck = State(initialValue: updater.automaticallyChecksForUpdates)
            _autoDownload = State(initialValue: updater.automaticallyDownloadsUpdates)
            _isBetaUsingStableFallback = State(initialValue: updater.isBetaUsingStableFallback)
        }
    }

    private var selectedChannel: UpdateChannel {
        UpdateChannel(rawValue: selectedChannelRaw) ?? .stable
    }

    var body: some View {
        Form {
            Section(header: Text("Software Updates")) {
                currentVersionRow

                Toggle("Automatically check for updates", isOn: Binding(
                    get: { autoCheck },
                    set: { newValue in
                        autoCheck = newValue
                        if !newValue {
                            autoDownload = false
                        }
                        guard !isMock else { return }
                        AppUpdater.shared.automaticallyChecksForUpdates = newValue
                        if !newValue {
                            AppUpdater.shared.automaticallyDownloadsUpdates = false
                        }
                    }
                ))

                Toggle(isOn: Binding(
                    get: { autoDownload },
                    set: { newValue in
                        autoDownload = newValue
                        guard !isMock else { return }
                        AppUpdater.shared.automaticallyDownloadsUpdates = newValue
                    }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Automatically download new updates")
                        Text("Automatically download new updates in the background when available.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .disabled(!autoCheck)

                VStack(alignment: .leading, spacing: 6) {
                    Picker("Update Channel", selection: $selectedChannelRaw) {
                        ForEach(UpdateChannel.allCases) { channel in
                            Text(channel.displayName).tag(channel.rawValue)
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(selectedChannel.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if selectedChannel == .beta, isBetaUsingStableFallback {
                            Text("No beta release is currently available. Checking stable updates instead.")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                }

                Button(action: checkForUpdates, label: {
                    Label("Check for Updates Now", systemImage: "arrow.triangle.2.circlepath")
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
        .onReceive(NotificationCenter.default.publisher(for: .appLockerBetaFallbackDidChange)) { _ in
            updateSparkleStatus()
        }
        .onChange(of: selectedChannelRaw) { _, _ in
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
        autoCheck = AppUpdater.shared.automaticallyChecksForUpdates
        autoDownload = AppUpdater.shared.automaticallyDownloadsUpdates
        hasAvailableUpdate = AppUpdater.shared.hasAvailableUpdate
        availableUpdateVersion = AppUpdater.shared.availableUpdateVersion ?? ""
        isBetaUsingStableFallback = AppUpdater.shared.isBetaUsingStableFallback
    }

    private func checkForUpdates() {
        guard !isMock else { return }
        AppUpdater.shared.checkForUpdates()
    }
}

#Preview {
    UpdatesSettingsTab(isMock: true)
}
