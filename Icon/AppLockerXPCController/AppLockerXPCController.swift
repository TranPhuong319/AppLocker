//
//  AppLockerXPCController.swift
//  AppLockerXPCController
//
//  Created by Doe Phương on 31/07/2025.
//

import Foundation

class AppLockerXPCController: NSObject, AppLockerXPCControllerProtocol {
    
    @objc public func performCalculation(firstNumber: Int, secondNumber: Int, with reply: @escaping (Int) -> Void) {
        let response = firstNumber + secondNumber
        reply(response)
    }

    @objc public func requestAdminAction(task: String, with reply: @escaping (Bool, String) -> Void) {
        // Your logic to perform the admin action
        // Make sure to modify based on your requirements

        let success: Bool = true // Replace with actual logic
        reply(success, success ? "Action performed successfully." : "Action failed.")
    }

    // You can add more methods as needed
}
