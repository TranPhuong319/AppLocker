//
//  AuthenticationManager.swift
//  AppLocker
//
//  Created by Doe Phương on 24/07/2025.
//


import Foundation
import LocalAuthentication

class AuthenticationManager {
    static func authenticate() -> Bool {
        let context = LAContext()
        var error: NSError?
        let reason = "Xác thực để mở ứng dụng bị khóa"

        if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) {
            var result = false
            let sema = DispatchSemaphore(value: 0)
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, err in
                result = success
                sema.signal()
            }
            sema.wait()
            return result
        } else {
            return false
        }
    }
}
