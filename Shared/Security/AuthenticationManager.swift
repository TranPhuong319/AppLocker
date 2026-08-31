//
//  AuthenticationManager.swift
//  AppLocker
//
//  Created by Doe Phương on 24/7/25.
//

import Foundation
@preconcurrency import LocalAuthentication

@MainActor
final class AuthenticationManager {
    private static var currentContext: LAContext?

    static func authenticate(reason: String,
                             completion: @MainActor @escaping (Bool, Error?) -> Void) {
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

        let contextID = ObjectIdentifier(context)
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, evalError in
            Task(priority: .high) { @MainActor in
                if let currentContext = self.currentContext, ObjectIdentifier(currentContext) == contextID {
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
