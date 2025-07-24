//
//  AppLockerApp.swift
//  AppLocker
//
//  Created by Doe Phương on 24/07/2025.
//

import SwiftUI

@main
struct AppLockerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            ContentView()
        }
    }
}
