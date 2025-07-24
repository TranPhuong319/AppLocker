//
//  AppLockerHelperProtocol 2.swift
//  AppLocker
//
//  Created by Doe Phương on 24/07/2025.
//


import Foundation

@objc protocol AppLockerHelperProtocol {
    func performAdminTask(_ task: String, withReply: @escaping (Bool, String) -> Void)
}