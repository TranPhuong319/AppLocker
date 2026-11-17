//
//  LaunchBootstrapPolicy.swift
//  AppLocker
//
//  Created by Doe Phương on 17/11/26.
//

import Foundation

enum SingleInstanceDecision: Equatable, Sendable {
    case proceed
    case terminateOtherManualInstances([Int32])
    case activateAndTerminateSelf(targetPID: Int32)
}

enum HandoverDecision: Equatable, Sendable {
    case terminateManualAndHandover
    case continueManual
}

enum LaunchBootstrapPolicy {
    @MainActor
    static func resolveHandover(
        isAgentActive: () -> Bool,
        installAgent: () -> Void,
        kickstart: () async -> Bool,
        forceReRegister: () -> Bool
    ) async -> HandoverDecision {
        if !isAgentActive() {
            installAgent()
        }
        guard isAgentActive() else {
            return .continueManual
        }
        if await kickstart() {
            return .terminateManualAndHandover
        }
        // RunAtLoad = true already spawns the agent on register(); a second kickstart -k triggers 10s throttle.
        return forceReRegister() ? .terminateManualAndHandover : .continueManual
    }

    static func resolveSingleInstance(
        isLaunchedByLaunchd: Bool,
        currentPID: Int32,
        ignoringPID: Int32? = nil,
        runningPIDs: [Int32]
    ) -> SingleInstanceDecision {
        let otherPIDs = runningPIDs.filter { $0 != currentPID && $0 != ignoringPID }
        guard let firstOther = otherPIDs.first else {
            return .proceed
        }
        return isLaunchedByLaunchd
            ? .terminateOtherManualInstances(otherPIDs)
            : .activateAndTerminateSelf(targetPID: firstOther)
    }
}
