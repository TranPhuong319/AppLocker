//
//  AuthenticationManager.swift
//  AppLocker
//
//  Created by Doe Phương on 24/07/2025.
//


import Foundation
import LocalAuthentication

class AuthenticationManager {
    static func authenticate(reason: String, completion: @escaping (Bool, String?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let context = LAContext()
            var error: NSError?

            if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) {
                context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, err in
                    DispatchQueue.main.async {
                        if success {
                            completion(true, nil)
                        } else {
                            let message = err?.localizedDescription ?? "Xác thực thất bại không rõ lý do"
                            completion(false, message)
                        }
                    }
                }
            } else {
                let message = error?.localizedDescription ?? "Không thể thực hiện xác thực trên thiết bị này"
                DispatchQueue.main.async {
                    completion(false, message)
                }
            }
        }
    }
}
