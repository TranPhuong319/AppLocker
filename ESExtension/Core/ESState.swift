//
//  ESState.swift
//  ESExtension
//
//  Created by Doe Phương on 29/12/25.
//

import Foundation

// Errors returned by es_new_client and related setup.
enum ESError: Error {
    case fullDiskAccessMissing
    case notRoot
    case entitlementMissing
    case tooManyClients
    case internalError
    case invalidArgument
    case unknown(Int32)
}

// Execution decision for a process.
enum ExecDecision {
    case allow
    case deny
}
