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
            .accentColor(Color("AccentColor")) // hoặc .blue nếu muốn chỉ định
        }
    }
}
