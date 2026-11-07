//
//  ESEventNotifyExec+Policy.swift
//  ESExtension
//
//  Created by Doe Phương on 4/11/26.
//

import Darwin
import Foundation
import os
import Security

// MARK: - Execution Lock Policy, Self-Execution Exemption & Incoming Call Bypass

extension ESManager {
    func isAppLockerSelfExecution(
        signingID: String,
        token: audit_token_t,
        pid: pid_t
    ) -> Bool {
        guard signingID == "com.TranPhuong319.AppLocker" else { return false }

        // Cryptographic Signature Verification
        if CodeSignatureValidator.validate(auditToken: token, requirement: CodeSignatureValidator.mainAppRequirement) {
            Logfile.endpointSecurity.info(
                """
                [NotifyExec] AppLocker self-execution verified & allowed, bypassing lock policy \
                (PID \(pid, privacy: .public))
                """
            )
            return true
        }
        return false
    }

    func isProcessBlocked(
        path: String,
        cdhashData: Data,
        cdhashHex: String,
        signingID: String = "Unsigned/Unknown",
        uid: uid_t
    ) -> Bool {
        let isZeroCDHash = cdhashData.allSatisfy { $0 == 0 }
        return stateLock.withLock { () -> Bool in
            if !isZeroCDHash, let userCDHashes = lockedCDHashes[uid], userCDHashes.contains(cdhashHex) {
                return true
            }
            if signingID != "Unsigned/Unknown" && !signingID.isEmpty,
               let userBundleIDs = lockedBundleIDs[uid],
               userBundleIDs.contains(signingID) {
                return true
            }
            return isPathInLockedBundle(path: path, uid: uid)
        }
    }

    func isPathInLockedBundle(path: String, uid: uid_t) -> Bool {
        guard let userBundlePaths = lockedBundlePaths[uid], !userBundlePaths.isEmpty else { return false }
        let normalizedExecPath = normalizeFirmlinkPath((path as NSString).standardizingPath)
        let bundleURL = URL(fileURLWithPath: normalizedExecPath).enclosingAppBundleURL
        guard bundleURL.pathExtension.lowercased() == "app" else { return false }

        let currentPath = bundleURL.path
        let stdPath = (currentPath as NSString).standardizingPath
        let normCurrent = normalizeFirmlinkPath(stdPath)
        let realBundlePath = normalizeFirmlinkPath(bundleURL.resolvingSymlinksInPath().path)
        let matchesBundle = userBundlePaths.contains(currentPath)
            || userBundlePaths.contains(stdPath)
            || userBundlePaths.contains(normCurrent)
            || userBundlePaths.contains(realBundlePath)

        if matchesBundle {
            let targetURL = userBundlePaths.contains(realBundlePath)
                ? URL(fileURLWithPath: realBundlePath)
                : bundleURL
            if let bundle = Bundle(url: targetURL), let mainExec = bundle.executablePath {
                let normPath = normalizeFirmlinkPath(URL(fileURLWithPath: path).resolvingSymlinksInPath().path)
                let normMainExec = normalizeFirmlinkPath(URL(fileURLWithPath: mainExec).resolvingSymlinksInPath().path)
                return normPath == normMainExec
            }
        }
        return false
    }

    func isAllowedIncomingCall(
        signingID: String,
        path: String,
        uid: uid_t
    ) -> Bool {
        let isTelephonyApp = signingID == "com.apple.FaceTime" || signingID == "com.apple.mobilephone"
            || path.contains("/FaceTime.app/") || path.contains("/Phone.app/")
        guard isTelephonyApp else { return false }

        let (userAllowsIncoming, isRinging, customValidator) = stateLock.withLock {
            (self.allowIncomingCallsByUID[uid] ?? true, self.isIncomingCallActive, self.telephonySignatureValidator)
        }
        guard userAllowsIncoming else { return false }

        let isCallActive = isRinging || isSharingActivityLevelPhoneCall()
        guard isCallActive else { return false }

        if let customValidator {
            return customValidator(path)
        }
        return isValidAppleTelephonyBinary(path: path)
    }

    private func isSharingActivityLevelPhoneCall() -> Bool {
        var token: Int32 = 0
        guard notify_register_check("com.apple.sharing.activity-level-changed", &token) == NOTIFY_STATUS_OK else {
            return false
        }
        defer { notify_cancel(token) }

        var state: UInt64 = 0
        guard notify_get_state(token, &state) == NOTIFY_STATUS_OK else {
            return false
        }

        Logfile.endpointSecurity.debug(
            "[NotifyExec] com.apple.sharing.activity-level-changed state: \(state, privacy: .public)"
        )

        return state == 14
    }

    private func isValidAppleTelephonyBinary(path: String) -> Bool {
        let url = URL(fileURLWithPath: path)
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode) == errSecSuccess,
              let code = staticCode else { return false }

        let reqString = "anchor apple and (identifier \"com.apple.mobilephone\" or identifier \"com.apple.FaceTime\")"
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(reqString as CFString, [], &requirement) == errSecSuccess,
              let req = requirement else { return false }

        return SecStaticCodeCheckValidity(code, [], req) == errSecSuccess
    }
}
