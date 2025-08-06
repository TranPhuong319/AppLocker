//
//  AppLockerServiceDelegate.swift
//  AppLocker
//
//  Created by Doe Phương on 31/07/2025.
//


import Foundation

class AppLockerServiceDelegate: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: AppLockerXPCControllerProtocol.self)
        connection.exportedObject = AppLockerXPCController()
        connection.resume()
        return true
    }
}

