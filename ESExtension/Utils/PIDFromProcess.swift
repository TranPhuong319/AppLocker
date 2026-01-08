//
//  PIDFromProcess.swift
//  ESExtension
//
//  Created by Doe Phương on 2/1/26.
//

import Foundation
import EndpointSecurity
import Darwin

@inline(__always)
func pidFromProcess(_ proc: UnsafePointer<es_process_t>) -> pid_t {
    audit_token_to_pid(proc.pointee.audit_token)
}
