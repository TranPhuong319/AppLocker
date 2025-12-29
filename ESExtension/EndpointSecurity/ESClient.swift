//
//  ESClient.swift
//  ESExtension
//
//  Created by Doe Phương on 29/12/25.
//

import Foundation
import EndpointSecurity
import os

extension ESManager {
    // Create ES client, subscribe to events, and start XPC.
    static func start(clientOwner: ESManager) throws {
        let res = es_new_client(&clientOwner.client) { client, message in
            ESManager.handleMessage(client: client, message: message)
        }

        if res != ES_NEW_CLIENT_RESULT_SUCCESS {
            Logfile.es.error("es_new_client failed with result: \(res.rawValue)")
            switch res {
            case ES_NEW_CLIENT_RESULT_ERR_NOT_PERMITTED:
                throw ESError.fullDiskAccessMissing
            case ES_NEW_CLIENT_RESULT_ERR_NOT_PRIVILEGED:
                throw ESError.notRoot
            case ES_NEW_CLIENT_RESULT_ERR_NOT_ENTITLED:
                throw ESError.entitlementMissing
            case ES_NEW_CLIENT_RESULT_ERR_TOO_MANY_CLIENTS:
                throw ESError.tooManyClients
            case ES_NEW_CLIENT_RESULT_ERR_INVALID_ARGUMENT:
                throw ESError.invalidArgument
            case ES_NEW_CLIENT_RESULT_ERR_INTERNAL:
                throw ESError.internalError
            default:
                throw ESError.unknown(Int32(res.rawValue))
            }
        }

        guard let client = clientOwner.client else {
            throw ESError.internalError
        }

        let execEvents: [es_event_type_t] = [
            ES_EVENT_TYPE_AUTH_EXEC
        ]

        if es_subscribe(client, execEvents, UInt32(execEvents.count)) != ES_RETURN_SUCCESS {
            Logfile.es.error("es_subscribe AUTH_EXEC failed")
        }

        ESManager.sharedInstanceForCallbacks = clientOwner

        // start auxiliary systems
        clientOwner.scheduleTempCleanup()
        clientOwner.setupMachListener()

        Logfile.es.log("ESManager (ESClient.start) started successfully")
    }

    // Tear down ES client and XPC connections cleanly.
    static func stop(clientOwner: ESManager) {
        if let client = clientOwner.client { es_delete_client(client) }
        clientOwner.client = nil

        ESManager.sharedInstanceForCallbacks = nil

        clientOwner.listener?.delegate = nil
        clientOwner.listener?.invalidate()
        clientOwner.listener = nil

        clientOwner.xpcLock.perform {
            for conn in clientOwner.activeConnections {
                conn.invalidate()
            }
            clientOwner.activeConnections.removeAll()
        }

        Logfile.es.log("ESManager stopped and cleaned up")
    }
}
