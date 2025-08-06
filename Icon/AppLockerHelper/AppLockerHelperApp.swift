//
//  AppLockerHelperApp.swift
//  AppLockerHelper
//
//  Created by Doe Phương on 30/07/2025.
//

import SwiftUI

@main
struct AppLockerHelperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        // Không tạo scene nào cả, để app không hiện gì
        Settings {
            EmptyView()
        }
    }
}
