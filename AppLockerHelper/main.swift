//
//  main.swift
//  AppLockerHelper
//
//  Created by Doe Phương on 04/08/2025.
//

import Foundation

let listener = NSXPCListener(machServiceName: "com.TranPhuong319.AppLocker.Helper")
let delegate = AppLockerHelper()
listener.delegate = delegate
listener.resume()
RunLoop.main.run()
