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
    
    var onInstalled: (() -> Void)?
    
    let identifier = "com.TranPhuong319.AppLocker.ESExtension"

    func install() {
        let req = OSSystemExtensionRequest.activationRequest(
            forExtensionWithIdentifier: identifier,
            queue: .main)
        req.delegate = self
        OSSystemExtensionManager.shared.submitRequest(req)
    }
    
    func uninstall() {
        let req = OSSystemExtensionRequest.deactivationRequest(
            forExtensionWithIdentifier: identifier,
            queue: .main)
        req.delegate = self
        OSSystemExtensionManager.shared.submitRequest(req)
    }
    
    // MARK: - OSSystemExtensionRequestDelegate
    
    func request(_ request: OSSystemExtensionRequest, didFinishWithResult result: OSSystemExtensionRequest.Result) {
        Logfile.core.info("[Installer] ✅ finished with result: \(result.rawValue)")
        
        if result == .completed {
            // Delay 1s rồi gọi callback
            DispatchQueue.main.async() {
                self.onInstalled?()
            }
        }
    }
    
    func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
        Logfile.core.error("[Installer] ❌ failed: \(error.localizedDescription)")
    }
    
    func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        Logfile.core.warning("[Installer] ⚠️ needs user approval in System Settings → Privacy & Security")
    }
    
    func request(_ request: OSSystemExtensionRequest, didFinishEarlyWithResult result: OSSystemExtensionRequest.Result) {
        Logfile.core.info("[Installer] ℹ️ finished early with result: \(result.rawValue)")
    }
    
    func request(_ request: OSSystemExtensionRequest,
                 actionForReplacingExtension existing: OSSystemExtensionProperties,
                 withExtension ext: OSSystemExtensionProperties
    ) -> OSSystemExtensionRequest.ReplacementAction {
        Logfile.core.info("[Installer] 🔄 Replacing extension \(existing.bundleIdentifier) v\(existing.bundleVersion) with v\(ext.bundleVersion)")
        return .replace
    }
}
