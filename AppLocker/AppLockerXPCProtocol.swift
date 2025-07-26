//
//  AppLockerXPCProtocol.swift
//  AppLocker
//
//  Created by Doe Phương on 26/07/2025.
//


import Foundation

@objc public protocol AppLockerXPCProtocol {
    func handleLaunchRequest(fromPID pid: Int32, appPath: String, withReply reply: @escaping (Bool) -> Void)
}
