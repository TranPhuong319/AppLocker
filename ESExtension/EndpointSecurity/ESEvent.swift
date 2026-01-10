//
//  ESEvent.swift
//  ESExtension
//
//  Created by Doe Phương on 29/12/25.
//

import Foundation
import EndpointSecurity
import os

extension ESManager {
    static func handleMessage(
        client: OpaquePointer?,
        message: UnsafePointer<es_message_t>?
    ) {
        guard let client = client, let message = message else { return }
        let type = message.pointee.event_type

        switch type {

        case ES_EVENT_TYPE_AUTH_EXEC:
            handleAuthExec(client: client, message: message)

        default:
            es_respond_auth_result(
                client,
                message,
                ES_AUTH_RESULT_ALLOW,
                false
            )
        }
    }
}
