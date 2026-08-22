//
//  ExtensionInstaller.swift
//  AppLocker
//
//  Created by Doe Phương on 27/9/25.
//

import Foundation
import Observation
import SystemExtensions

@Observable
@MainActor
final class ExtensionInstaller: NSObject, OSSystemExtensionRequestDelegate {
    static let shared = ExtensionInstaller()
    private override init() {}

    private(set) var isInstalled: Bool = false

    private enum Action {
        case install(completion: ((Result<Void, Error>) -> Void)?)
        case uninstall(completion: ((Result<Void, Error>) -> Void)?)
    }

    private var currentAction: Action?

    let identifier = "com.TranPhuong319.AppLocker.ESExtension"

    func updateInstalledState(_ installed: Bool) {
        isInstalled = installed
    }

    func install(completion: ((Result<Void, Error>) -> Void)? = nil) {
        currentAction = .install(completion: completion)
        let req = OSSystemExtensionRequest.activationRequest(
            forExtensionWithIdentifier: identifier,
            queue: .main
        )
        req.delegate = self
        OSSystemExtensionManager.shared.submitRequest(req)
    }

    func uninstall(completion: ((Result<Void, Error>) -> Void)? = nil) {
        currentAction = .uninstall(completion: completion)
        let req = OSSystemExtensionRequest.deactivationRequest(
            forExtensionWithIdentifier: identifier,
            queue: .main
        )
        req.delegate = self
        OSSystemExtensionManager.shared.submitRequest(req)
    }

    // MARK: - OSSystemExtensionRequestDelegate

    nonisolated func request(_ request: OSSystemExtensionRequest,
                             didFinishWithResult result: OSSystemExtensionRequest.Result) {
        Task { @MainActor in
            self.handleFinish(result: result)
        }
    }

    nonisolated func request(_ request: OSSystemExtensionRequest,
                             didFinishEarlyWithResult result: OSSystemExtensionRequest.Result) {
        Logfile.core.info("[Installer] finished early: \(result.rawValue)")
        Task { @MainActor in
            self.handleFinish(result: result)
        }
    }

    private func handleFinish(result: OSSystemExtensionRequest.Result) {
        guard result == .completed else { return }

        switch currentAction {
        case .install(let completion):
            isInstalled = true
            ESXPCClient.shared.connect()
            completion?(.success(()))
        case .uninstall(let completion):
            isInstalled = false
            ESXPCClient.shared.disconnect()
            completion?(.success(()))
        case .none:
            break
        }

        currentAction = nil
    }

    nonisolated func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
        Task { @MainActor in
            self.isInstalled = false
            ESXPCClient.shared.disconnect()
            let action = self.currentAction
            self.currentAction = nil

            switch action {
            case .install(let completion):
                Logfile.core.error("[Installer] install failed: \(error.localizedDescription)")
                completion?(.failure(error))
            case .uninstall(let completion):
                Logfile.core.error("[Installer] uninstall failed: \(error.localizedDescription)")
                completion?(.failure(error))
            case .none:
                Logfile.core.error("[Installer] operation failed: \(error.localizedDescription)")
            }
        }
    }

    nonisolated func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        Task { @MainActor in
            self.isInstalled = false
            ESXPCClient.shared.disconnect()
            Logfile.core.warning("[Installer] needs user approval")
        }
    }

    nonisolated func request(_ request: OSSystemExtensionRequest,
                             actionForReplacingExtension existing: OSSystemExtensionProperties,
                             withExtension ext: OSSystemExtensionProperties
    ) -> OSSystemExtensionRequest.ReplacementAction {
        return .replace
    }
}
