//
//  ESAuthorizer.swift
//  ESExtension
//
//  Created by Doe Phương on 4/10/26.
//

import EndpointSecurity
import Foundation

final class ESAuthorizer: ESClientObject, @unchecked Sendable {
    init() { super.init(name: "Authorizer") }
    func start() -> Bool { createClient() }

    func enable() {
        _ = self.subscribe([
            ES_EVENT_TYPE_NOTIFY_EXEC,
            ES_EVENT_TYPE_AUTH_SIGNAL,
            ES_EVENT_TYPE_NOTIFY_EXIT
        ])
    }
}
