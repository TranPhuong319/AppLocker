//
//  ESTamper.swift
//  ESExtension
//
//  Created by Doe Phương on 4/10/26.
//

import EndpointSecurity
import Foundation
import os

final class ESTamper: ESClientObject, @unchecked Sendable {
    init() { super.init(name: "TamperResistance") }
    func start() -> Bool { createClient() }

    func enable() {
        #if DEBUG
        Logfile.endpointSecurity.debug("[ESClient] Skip enable ESTamper (Debug mode)")
        #else
        self.muteSelf()
        Logfile.endpointSecurity.debug(
            "[ESClient] [\(self.name, privacy: .public)] Enabling Inverted Muting (Santa-Style)..."
        )
        if let client = self.client {
            _ = es_unmute_all_target_paths(client)
            let invRes = es_invert_muting(client, ES_MUTE_INVERSION_TYPE_TARGET_PATH)
            Logfile.endpointSecurity.debug(
                "[ESClient] [\(self.name, privacy: .public)] Invert muting result: \(invRes.rawValue, privacy: .public)"
            )
        }
        self.setupAllowlist()
        _ = self.subscribe([
            ES_EVENT_TYPE_AUTH_OPEN,
            ES_EVENT_TYPE_AUTH_UNLINK,
            ES_EVENT_TYPE_AUTH_RENAME,
            ES_EVENT_TYPE_AUTH_TRUNCATE,
            ES_EVENT_TYPE_AUTH_EXCHANGEDATA,
            ES_EVENT_TYPE_AUTH_CLONE,
            ES_EVENT_TYPE_AUTH_LINK
        ])
        #endif
    }

    private func setupAllowlist() {
        let paths: [(path: String, type: es_mute_path_type_t)] = [
            ("/Users/Shared/AppLocker", ES_MUTE_PATH_TYPE_TARGET_PREFIX),
            ("/Applications/AppLocker.app", ES_MUTE_PATH_TYPE_TARGET_PREFIX)
        ]
        if let client = self.client {
            for item in paths {
                let res = es_mute_path(client, item.path, item.type)
                Logfile.endpointSecurity.debug(
                    """
                    [ESClient] [\(self.name, privacy: .public)] Allowlist [\(item.path, privacy: .public)] \
                    result: \(res.rawValue, privacy: .public)
                    """
                )
            }
        }
    }
}
