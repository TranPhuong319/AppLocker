//
//  AuthenticationManager.swift
//  AppLocker
//
//  Copyright © 2025 TranPhuong319. All rights reserved.
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
                            let message = err?.localizedDescription ?? "The_authentication_fails_for_unknown_reasons".localized
                            completion(false, message)
                        }
                    }
                }
            } else {
                let message = error?.localizedDescription ?? "It_is_impossible_to_perform_on_this_device".localized
                DispatchQueue.main.async {
                    completion(false, message)
                }
            }
        }
    }
}
