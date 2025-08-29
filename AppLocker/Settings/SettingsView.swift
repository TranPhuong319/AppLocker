//
//  SettingsView.swift
//  AppLocker
//
//  Created by Doe Phương on 26/8/25.
//

import SwiftUI
import Sparkle

struct SettingsView: View {
    @State private var autoCheck = AppUpdater.shared.updaterController.updater.automaticallyChecksForUpdates
    @State private var autoDownload = AppUpdater.shared.updaterController.updater.automaticallyDownloadsUpdates

    var body: some View {
        Form {
            Toggle("Automatically check for updates.".localized, isOn: $autoCheck)
                .onChange(of: autoCheck) { newValue in
                    AppUpdater.shared.updaterController.updater.automaticallyChecksForUpdates = newValue
                }

            Toggle("Automatically download new updates.".localized, isOn: $autoDownload)
                .onChange(of: autoDownload) { newValue in
                    AppUpdater.shared.updaterController.updater.automaticallyDownloadsUpdates = newValue
                }
        }
        .padding()
        .frame(width: 300)
    }
}

#Preview{
    SettingsView()
}
