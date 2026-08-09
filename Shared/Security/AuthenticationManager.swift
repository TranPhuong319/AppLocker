//
//  AuthenticationManager.swift
//  AppLocker
//
//  Created by Doe Phương on 24/7/25.
//

import Foundation
import LocalAuthentication

@MainActor
final class AuthenticationManager {
    private static var currentContext: LAContext?

    static func authenticate(reason: String,
                             completion: @escaping (Bool, Error?) -> Void) {
        let context = LAContext()
        self.currentContext = context

        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            if self.currentContext === context {
                self.currentContext = nil
            }
            completion(false, error)
            return
        }

        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, evalError in
            Task { @MainActor in
                if self.currentContext === context {
                    self.currentContext = nil
                }
                completion(success, evalError)
            }
        }
    }

    static func cancelCurrentAuthentication() {
        currentContext?.invalidate()
        currentContext = nil
    }
}
