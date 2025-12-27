//
//  ExtensionInstaller.swift
//  AppLocker
//
//  Created by Doe Phương on 27/9/25.
//

import Foundation
import SystemExtensions

final class ExtensionInstaller: NSObject, OSSystemExtensionRequestDelegate {
    static let shared = ExtensionInstaller()
    private override init() {}

    enum Action {
        case install
        case uninstall
    }

    private var currentAction: Action?

    var onInstalled: (() -> Void)?
    var onUninstalled: (() -> Void)?

    let identifier = "com.TranPhuong319.AppLocker.ESExtension"

    func install() {
        currentAction = .install
        let req = OSSystemExtensionRequest.activationRequest(
            forExtensionWithIdentifier: identifier,
            queue: .main
        )
        req.delegate = self
        OSSystemExtensionManager.shared.submitRequest(req)
    }

    func uninstall() {
        currentAction = .uninstall
        let req = OSSystemExtensionRequest.deactivationRequest(
            forExtensionWithIdentifier: identifier,
            queue: .main
        )
        req.delegate = self
        OSSystemExtensionManager.shared.submitRequest(req)
    }

    // MARK: - OSSystemExtensionRequestDelegate

    func request(_ request: OSSystemExtensionRequest,
                 didFinishWithResult result: OSSystemExtensionRequest.Result) {

        guard result == .completed else { return }

        switch currentAction {
        case .install:
            onInstalled?()
        case .uninstall:
            onUninstalled?()
        case .none:
            break
        }

        currentAction = nil
    }

    func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
        currentAction = nil
        Logfile.core.error("[Installer] failed: \(error.localizedDescription)")
    }

    func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        Logfile.core.warning("[Installer] needs user approval")
    }

    func request(_ request: OSSystemExtensionRequest,
                 didFinishEarlyWithResult result: OSSystemExtensionRequest.Result) {
        Logfile.core.info("[Installer] finished early: \(result.rawValue)")
    }

    func request(_ request: OSSystemExtensionRequest,
                 actionForReplacingExtension existing: OSSystemExtensionProperties,
                 withExtension ext: OSSystemExtensionProperties
    ) -> OSSystemExtensionRequest.ReplacementAction {
        return .replace
    }
}
