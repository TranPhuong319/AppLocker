//
//  AppearanceSettingsTab.swift
//  AppLocker
//
//  Created by Doe Phương on 18/8/25.
//

import SwiftUI

struct AppearanceSettingsTab: View {
    let isMock: Bool

    @AppStorage("appTheme") private var appTheme: String = "System"

    var body: some View {
        Form {
            Section(header: Text("Theme")) {
                Picker("Theme Mode", selection: $appTheme) {
                    Text("System Default").tag("System")
                    Text("Light Mode").tag("Light")
                    Text("Dark Mode").tag("Dark")
                }
                .pickerStyle(.radioGroup)
                .onChange(of: appTheme) { newValue in
                    if !isMock, let appDelegate = NSApp.delegate as? AppDelegate {
                        appDelegate.applyTheme(newValue)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

#Preview {
    AppearanceSettingsTab(isMock: true)
}
