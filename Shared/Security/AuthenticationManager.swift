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
        defer {
            if self.currentContext === context {
                self.currentContext = nil
            }
        }

        var canEvaluateError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &canEvaluateError) else {
            if let canEvaluateError {
                throw canEvaluateError
            }
            return false
        }

        return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
    }

    static func cancelCurrentAuthentication() {
        currentContext?.invalidate()
        currentContext = nil
    }
}
