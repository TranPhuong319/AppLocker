//
//  AuthenticationManager.swift
//  AppLocker
//
//  Created by Doe Phương on 24/7/25.
//

import Foundation
import LocalAuthentication
import os

@MainActor
final class AuthenticationManager {
    private static var esContext: LAContext?
    private static var uiContext: LAContext?
    private static var supersededUIContexts: Set<ObjectIdentifier> = []

    static func authenticate(reason: String, isEndpointSecurity: Bool = false) async throws -> Bool {
        let context = LAContext()
        let contextID = ObjectIdentifier(context)

        if isEndpointSecurity {
            if let activeUI = uiContext {
                supersededUIContexts.insert(ObjectIdentifier(activeUI))
                activeUI.invalidate()
                uiContext = nil
            }
            self.esContext = context
        } else {
            self.uiContext = context
        }

        defer {
            if isEndpointSecurity {
                if self.esContext === context { self.esContext = nil }
            } else {
                if self.uiContext === context { self.uiContext = nil }
                self.supersededUIContexts.remove(contextID)
            }
        }

        var canEvaluateError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &canEvaluateError) else {
            if let canEvaluateError {
                throw canEvaluateError
            }
            return false
        }

        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        } catch {
            if !isEndpointSecurity && supersededUIContexts.contains(contextID) {
                Logfile.app.debug("[Auth] UI authentication superseded cleanly by Endpoint Security prompt")
                return false
            }
            throw error
        }
    }

    static func cancelCurrentAuthentication() {
        esContext?.invalidate()
        esContext = nil
    }
}
