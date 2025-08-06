//
//  AppDelegate.swift
//  AppLocker
//
//  Created by Doe Phương on 31/07/2025.
//


//
//  AppDelegate.swift
//  AppLocker
//
//  Created by Doe Phương on 30/07/2025.
//


import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {
    var listener: NSXPCListener?
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        print("✅ AppLockerHelper is running...")

        NSApp.setActivationPolicy(.prohibited)

        // Start listener
        listener = NSXPCListener.anonymous()
        listener?.delegate = AppLockerServiceDelegate()
        listener?.resume()
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        print("AppLockerHelper terminated.")
    }
}
