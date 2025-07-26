//
//  AppLockerXPCDelegate.swift
//  AppLocker
//
//  Created by Doe Phương on 26/07/2025.
//


import Foundation

class AppLockerXPCDelegate: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        newConnection.exportedInterface = NSXPCInterface(with: AppLockerXPCProtocol.self)
        newConnection.exportedObject = AppLockerXPCService()
        newConnection.resume()
        return true
    }
}
