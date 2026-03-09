//
//  SettingsView.swift
//  AppLocker
//
//  Created by Doe Phương on 18/8/25.
//

import SwiftUI
import Sparkle

enum UpdateChannel: String, CaseIterable, Identifiable {
    case stable = "Stable"  // giá trị cố định cho code / lưu UserDefaults
    case beta = "Beta"

    var id: String { self.rawValue }

    // Hiển thị tên cho UI, có thể localize
    var displayName: LocalizedStringKey {
        switch self {
        case .stable: return "Stable"
        case .beta: return "Beta"
        }
    }
    var description: LocalizedStringKey {
        switch self {
        case .stable:
            return "Get official, stable updates."
        case .beta:
            return """
                Get experimental updates.
                Note: Experimental updates are often unstable.
                """
        }
    }
}

struct SettingsView: View {
    @State private var autoCheck: Bool
    @State private var autoDownload: Bool
    private var isMock: Bool

    // Lấy giá trị từ UserDefaults hoặc mặc định là Stable
    @State private var selectedChannel: UpdateChannel

    init(autoCheck: Bool = false, autoDownload: Bool = false, selectedChannel: UpdateChannel = .stable, isMock: Bool = false) {
        _autoCheck = State(initialValue: autoCheck)
        _autoDownload = State(initialValue: autoDownload)
        _selectedChannel = State(initialValue: selectedChannel)
        self.isMock = isMock
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Form {
                Section {
                    Group {
                        Toggle("Automatically check for updates.", isOn: $autoCheck)
                            .onChange(of: autoCheck) { newValue in
                                if !isMock {
                                    let updater = AppUpdater.shared.updaterController.updater
                                    updater.automaticallyChecksForUpdates = newValue
                                }

                                if !newValue {
                                    autoDownload = false
                                    if !isMock {
                                        AppUpdater.shared.updaterController.updater.automaticallyDownloadsUpdates = false
                                    }
                                }

                                #if DEBUG
                                if newValue && !isMock {
                                    AppUpdater.shared.debugForceCheckIfPossible()
                                }
                                #endif
                            }

                        Toggle("Automatically download new updates.", isOn: $autoDownload)
                            .disabled(!autoCheck)
                            .onChange(of: autoDownload) { newValue in
                                if !isMock {
                                    let updater = AppUpdater.shared.updaterController.updater
                                    updater.automaticallyDownloadsUpdates = newValue
                                }

                                #if DEBUG
                                if newValue && !isMock {
                                    AppUpdater.shared.debugForceCheckIfPossible()
                                }
                                #endif
                            }
                    }
                    Picker("Update Channel", selection: $selectedChannel) {
                        ForEach(UpdateChannel.allCases, id: \.self) { channel in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(channel.displayName)
                                    .font(.body)
                            }
                            .tag(channel)
                        }
                    }
                    .onChange(of: selectedChannel) { newChannel in
                        if !isMock {
                            UserDefaults.standard.set(newChannel.rawValue, forKey: "updateChannel")
                        }
                    }

                    // Text mô tả, tự động thay đổi theo selectedChannel
                    Text(selectedChannel.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(nil)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 2)
                }
            }
        }
        .fixedSize()
        .padding()
        .onAppear {
            guard !isMock else { return }
            let updater = AppUpdater.shared.updaterController.updater
            autoCheck = updater.automaticallyChecksForUpdates
            autoDownload = updater.automaticallyDownloadsUpdates
        }
    }
}

#Preview("No Check & No Download") {
    SettingsView(autoCheck: false, autoDownload: false, isMock: true)
}

#Preview("Auto Check Only") {
    SettingsView(autoCheck: true, autoDownload: false, isMock: true)
}

#Preview("Auto Check & Download") {
    SettingsView(autoCheck: true, autoDownload: true, isMock: true)
}

#Preview("Stable Channel") {
    SettingsView(selectedChannel: .stable, isMock: true)
}

#Preview("Beta Channel") {
    SettingsView(selectedChannel: .beta, isMock: true)
}
