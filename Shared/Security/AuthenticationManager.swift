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

    static func authenticate(reason: String) async throws -> Bool {
        let context = LAContext()
        self.currentContext = context

        var canEvaluateError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &canEvaluateError) else {
            if self.currentContext === context {
                self.currentContext = nil
            }
            if let canEvaluateError {
                throw canEvaluateError
            }
            return false
        }

        let contextID = ObjectIdentifier(context)
        return try await withCheckedThrowingContinuation { continuation in
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, evalError in
                Task { @MainActor in
                    if let currentContext = self.currentContext, ObjectIdentifier(currentContext) == contextID {
                        self.currentContext = nil
                    }
                    if let evalError {
                        continuation.resume(throwing: evalError)
                    } else {
                        continuation.resume(returning: success)
                    }
                }
            }
        }
    }

    static func cancelCurrentAuthentication() {
        currentContext?.invalidate()
        currentContext = nil
    }
}
