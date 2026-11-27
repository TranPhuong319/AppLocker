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
    nonisolated static let extensionIdentifier = "com.TranPhuong319.AppLocker.ESExtension"

    private let userDefaults: UserDefaults
    private let isTesting: Bool
    private let onRefreshStatus: ((Bool) -> Void)?
    private let onConnect: () -> Void
    private let onDisconnect: () -> Void

    init(
        userDefaults: UserDefaults = .standard,
        isTesting: Bool = false,
        onRefreshStatus: ((Bool) -> Void)? = nil,
        onConnect: @escaping () -> Void = { ESXPCClient.shared.connect() },
        onDisconnect: @escaping () -> Void = { ESXPCClient.shared.disconnect() }
    ) {
        self.userDefaults = userDefaults
        self.isTesting = isTesting
        self.onRefreshStatus = onRefreshStatus
        self.onConnect = onConnect
        self.onDisconnect = onDisconnect
        self.isInstalled = userDefaults.bool(forKey: "isExtensionInstalled")
        super.init()
        guard !isTesting else { return }
        if #available(macOS 15.1, *) {
            do {
                try OSSystemExtensionsWorkspace.shared.addObserver(self)
                Logfile.app.debug("[Installer] OSSystemExtensionsWorkspace observer registered.")
            } catch {
                Logfile.app.error(
                    "[Installer] Failed to add workspace observer: \(error.localizedDescription, privacy: .public)"
                )
            }
        }
        refreshStatus()
    }

    func refreshStatus(reconnectIfEnabled: Bool = true) {
        if let onRefreshStatus {
            onRefreshStatus(reconnectIfEnabled)
            return
        }
        let req = OSSystemExtensionRequest.propertiesRequest(
            forExtensionWithIdentifier: Self.extensionIdentifier,
            queue: .main
        )
        if !reconnectIfEnabled {
            skipReconnectRequestIDs.insert(ObjectIdentifier(req))
        }
        req.delegate = self
        OSSystemExtensionManager.shared.submitRequest(req)
    }

    nonisolated static var isExtensionInstalled: Bool {
        UserDefaults.standard.bool(forKey: "isExtensionInstalled")
    }

    private(set) var isInstalled: Bool = false {
        didSet {
            guard oldValue != isInstalled else { return }
            userDefaults.set(isInstalled, forKey: "isExtensionInstalled")
            NotificationCenter.default.post(name: .protectionStatusDidChange, object: nil)
        }
    }

    private enum Action {
        case install(completion: ((Result<Void, Error>) -> Void)?)
        case uninstall(completion: ((Result<Void, Error>) -> Void)?)
    }

    private var currentAction: Action?
    private var skipReconnectRequestIDs: Set<ObjectIdentifier> = []

    var identifier: String { Self.extensionIdentifier }

    func updateInstalledState(_ installed: Bool) {
        isInstalled = installed
    }

    func install(completion: ((Result<Void, Error>) -> Void)? = nil) {
        currentAction = .install(completion: completion)
        guard !isTesting else { return }
        let req = OSSystemExtensionRequest.activationRequest(
            forExtensionWithIdentifier: identifier,
            queue: .main
        )
        req.delegate = self
        OSSystemExtensionManager.shared.submitRequest(req)
    }

    func uninstall(completion: ((Result<Void, Error>) -> Void)? = nil) {
        currentAction = .uninstall(completion: completion)
        guard !isTesting else { return }
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
        let requestID = ObjectIdentifier(request)
        Task { @MainActor in
            self.skipReconnectRequestIDs.remove(requestID)
            self.handleFinish(result: result)
        }
    }

    nonisolated func request(_ request: OSSystemExtensionRequest,
                             didFinishEarlyWithResult result: OSSystemExtensionRequest.Result) {
        let requestID = ObjectIdentifier(request)
        Logfile.app.debug("[Installer] Finished early: \(result.rawValue, privacy: .public)")
        Task { @MainActor in
            self.skipReconnectRequestIDs.remove(requestID)
            self.handleFinish(result: result)
        }
    }

    func handleFinish(result: OSSystemExtensionRequest.Result) {
        guard result == .completed || result == .willCompleteAfterReboot else { return }

        switch currentAction {
        case .install(let completion):
            if result == .completed {
                // Activation completion does not guarantee the extension is enabled in System Settings.
                refreshStatus(reconnectIfEnabled: true)
            } else {
                isInstalled = false
            }
            completion?(.success(()))
        case .uninstall(let completion):
            isInstalled = false
            onDisconnect()
            completion?(.success(()))
        case .none:
            break
        }

        currentAction = nil
    }

    nonisolated func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
        let requestID = ObjectIdentifier(request)
        ESXPCClient.shared.disconnect()
        Task { @MainActor in
            self.skipReconnectRequestIDs.remove(requestID)
            self.isInstalled = false
            let action = self.currentAction
            self.currentAction = nil

            switch action {
            case .install(let completion):
                Logfile.app.error("[Installer] Install failed: \(error.localizedDescription)")
                completion?(.failure(error))
            case .uninstall(let completion):
                Logfile.app.error("[Installer] Uninstall failed: \(error.localizedDescription)")
                completion?(.failure(error))
            case .none:
                Logfile.app.error("[Installer] Operation failed: \(error.localizedDescription)")
            }
        }
    }

    nonisolated func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        let requestID = ObjectIdentifier(request)
        ESXPCClient.shared.disconnect()
        Task { @MainActor in
            self.skipReconnectRequestIDs.remove(requestID)
            self.isInstalled = false
            if case .uninstall(let completion) = self.currentAction {
                self.currentAction = nil
                completion?(.failure(OSSystemExtensionError(.authorizationRequired)))
            }
            Logfile.app.warning("[Installer] Extension requires user approval in System Settings")
        }
    }

    nonisolated func request(_ request: OSSystemExtensionRequest,
                             actionForReplacingExtension existing: OSSystemExtensionProperties,
                             withExtension ext: OSSystemExtensionProperties
    ) -> OSSystemExtensionRequest.ReplacementAction {
        return .replace
    }

    nonisolated func request(
        _ request: OSSystemExtensionRequest,
        foundProperties properties: [OSSystemExtensionProperties]
    ) {
        let requestID = ObjectIdentifier(request)
        let isEnabled = properties.contains { $0.isEnabled }
        Task { @MainActor in
            let shouldReconnect = self.skipReconnectRequestIDs.remove(requestID) == nil
            self.applyPropertiesResult(isEnabled: isEnabled, shouldReconnect: shouldReconnect)
        }
    }

    func applyPropertiesResult(isEnabled: Bool, shouldReconnect: Bool) {
        isInstalled = isEnabled
        // Always notify: menubar icon may be stale because setupMenuBar runs
        // before this async callback returns (even when value is unchanged).
        NotificationCenter.default.post(name: .protectionStatusDidChange, object: nil)
        Logfile.app.info("[Installer] Extension properties checked: isEnabled=\(isEnabled, privacy: .public)")
        if isEnabled {
            if shouldReconnect {
                onConnect()
            }
        } else {
            onDisconnect()
        }
    }
}

// MARK: - OSSystemExtensionsWorkspaceObserver (macOS 15.1+)
@available(macOS 15.1, *)
extension ExtensionInstaller: OSSystemExtensionsWorkspaceObserver {
    nonisolated func systemExtensionWillBecomeEnabled(_ systemExtensionInfo: OSSystemExtensionInfo) {
        guard systemExtensionInfo.bundleIdentifier == ExtensionInstaller.extensionIdentifier else { return }
        Task { @MainActor in
            self.isInstalled = true
            ESXPCClient.shared.connect()
            Logfile.app.notice(
                "[Installer] System extension enabled: \(systemExtensionInfo.bundleIdentifier, privacy: .public)"
            )
        }
    }

    nonisolated func systemExtensionWillBecomeDisabled(_ systemExtensionInfo: OSSystemExtensionInfo) {
        guard systemExtensionInfo.bundleIdentifier == ExtensionInstaller.extensionIdentifier else { return }
        ESXPCClient.shared.disconnect()
        Task { @MainActor in
            self.isInstalled = false
            Logfile.app.warning(
                "[Installer] System extension disabled: \(systemExtensionInfo.bundleIdentifier, privacy: .public)"
            )
        }
    }

    nonisolated func systemExtensionWillBecomeInactive(_ systemExtensionInfo: OSSystemExtensionInfo) {
        guard systemExtensionInfo.bundleIdentifier == ExtensionInstaller.extensionIdentifier else { return }
        ESXPCClient.shared.disconnect()
        Task { @MainActor in
            self.isInstalled = false
            Logfile.app.warning(
                "[Installer] System extension inactive: \(systemExtensionInfo.bundleIdentifier, privacy: .public)"
            )
        }
    }
}
