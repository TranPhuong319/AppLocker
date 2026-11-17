//
//  LaunchHandoverAndSingleInstanceTests.swift
//  AppLockerTests
//
//  Created by Doe Phương on 17/11/26.
//

import Foundation
import Testing

@Suite("Launch Handover & Single-Instance Policy Tests")
struct LaunchHandoverAndSingleInstanceTests {

    @Test("Manual launch hands over to launchd immediately when kickstart succeeds")
    func manualHandoverSucceedsOnFirstKickstart() async {
        var kickstartCalls = 0
        var forceReRegisterCalls = 0

        let decision = await LaunchBootstrapPolicy.resolveHandover(
            isAgentActive: { true },
            installAgent: { Issue.record("installAgent should not be called when already active") },
            kickstart: {
                kickstartCalls += 1
                return true
            },
            forceReRegister: {
                forceReRegisterCalls += 1
                return true
            }
        )

        #expect(decision == .terminateManualAndHandover)
        #expect(kickstartCalls == 1)
        #expect(forceReRegisterCalls == 0)
    }

    @Test("Manual launch after bootout force re-registers once without second kickstart")
    func manualHandoverAfterBootoutSkipsSecondKickstart() async {
        var kickstartCalls = 0
        var forceReRegisterCalls = 0

        let decision = await LaunchBootstrapPolicy.resolveHandover(
            isAgentActive: { true },
            installAgent: {},
            kickstart: {
                kickstartCalls += 1
                return false
            },
            forceReRegister: {
                forceReRegisterCalls += 1
                return true
            }
        )

        #expect(decision == .terminateManualAndHandover)
        #expect(kickstartCalls == 1)
        #expect(forceReRegisterCalls == 1)
    }

    @Test("Manual launch continues directly when agent cannot be activated")
    func manualContinuesWhenAgentInstallFails() async {
        var installCalls = 0
        var kickstartCalls = 0

        let decision = await LaunchBootstrapPolicy.resolveHandover(
            isAgentActive: { false },
            installAgent: { installCalls += 1 },
            kickstart: {
                kickstartCalls += 1
                return true
            },
            forceReRegister: { true }
        )

        #expect(decision == .continueManual)
        #expect(installCalls == 1)
        #expect(kickstartCalls == 0)
    }

    @Test("Manual launch falls back to running directly when kickstart and re-register fail")
    func manualFallsBackWhenBothKickstartAndReRegisterFail() async {
        let decision = await LaunchBootstrapPolicy.resolveHandover(
            isAgentActive: { true },
            installAgent: {},
            kickstart: { false },
            forceReRegister: { false }
        )

        #expect(decision == .continueManual)
    }

    @Test("Spawning duplicate manual process activates existing instance and terminates new one")
    func duplicateManualProcessTerminatesSelf() {
        let decision = LaunchBootstrapPolicy.resolveSingleInstance(
            isLaunchedByLaunchd: false,
            currentPID: 9171,
            runningPIDs: [9166, 9171]
        )

        #expect(decision == .activateAndTerminateSelf(targetPID: 9166))
    }

    @Test("Launchd instance terminates lingering manual instance instead of terminating itself")
    func launchdInstanceTakesOverFromManualInstance() {
        let decision = LaunchBootstrapPolicy.resolveSingleInstance(
            isLaunchedByLaunchd: true,
            currentPID: 9171,
            runningPIDs: [9166, 9171]
        )

        #expect(decision == .terminateOtherManualInstances([9166]))
    }

    @Test("Relaunch ignores exiting parent PID via -waitForPID and proceeds")
    func relaunchIgnoresParentPID() {
        let decision = LaunchBootstrapPolicy.resolveSingleInstance(
            isLaunchedByLaunchd: false,
            currentPID: 2002,
            ignoringPID: 2001,
            runningPIDs: [2001, 2002]
        )

        #expect(decision == .proceed)
    }
}
