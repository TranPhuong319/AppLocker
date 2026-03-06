//
//  main.swift
//  AppLockerEndpointSecurity
//
//  Created by Doe Phương on 26/9/25.
//

import Foundation

// Keep a strong global reference to prevent deallocation
private var manager: ESManager?

autoreleasepool {
    manager = ESManager()
    dispatchMain()
}
