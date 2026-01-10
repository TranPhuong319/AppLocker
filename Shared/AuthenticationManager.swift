//
//  AuthenticationManager.swift
//  AppLocker
//
//  Copyright © 2025 TranPhuong319. All rights reserved.
//

import Foundation
import LocalAuthentication

final class AuthenticationManager {
    static func authenticate(reason: String,
                             completion: @escaping (Bool, Error?) -> Void) {
        let context = LAContext()
        var error: NSError?

        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            DispatchQueue.main.async {
                completion(false, error)
            }
            return
        }

        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, evalError in
            DispatchQueue.main.async {
                completion(success, evalError)
            }
        }
    }
}
