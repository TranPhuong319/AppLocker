//
//  AppLockerHelperProtocol.swift
//  AppLockerHelper
//
//  Created by Doe Phương on 04/08/2025.
//

import Foundation

@objc protocol AppLockerHelperProtocol {
    func sendBatch(_ commands: [[String: Any]], withReply reply: @escaping (Bool, String) -> Void)
}

