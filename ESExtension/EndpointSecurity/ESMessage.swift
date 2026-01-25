//
//  ESMessage.swift
//  ESExtension
//
//  Created by AppLocker on 22/1/26.
//

import EndpointSecurity
import Foundation

/// RAII Wrapper for es_message_t, following Santa's pattern.
/// Retains the message on initialization (on the kernel thread) and releases it on deinitialization.
class ESMessage {
    let rawMessage: UnsafePointer<es_message_t>
    let client: OpaquePointer

    /// - Parameters:
    ///   - client: The es_client_t pointer.
    ///   - message: The raw es_message_t pointer.
    /// - Note: This MUST be initialized directly within the es_new_client callback block.
    init(client: OpaquePointer, message: UnsafePointer<es_message_t>) {
        self.client = client
        self.rawMessage = message
        es_retain_message(message)
    }

    deinit {
        es_release_message(rawMessage)
    }

    /// Accessor for the underlying message structure
    var pointee: es_message_t {
        return rawMessage.pointee
    }

    /// Accessor for the raw pointer (use carefully)
    var pointer: UnsafePointer<es_message_t> {
        return rawMessage
    }
}
