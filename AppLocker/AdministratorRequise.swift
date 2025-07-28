//
//  AdministratorRequise.swift
//  AppLocker
//
//  Created by Doe Phương on 26/07/2025.
//

import Foundation

func runPrivilegedScript(appPaths: [String], completion: @escaping (Bool) -> Void) {
    let script = appPaths.map { path in
        let safePath = path.replacingOccurrences(of: "\"", with: "\\\"")
        return """
        if [ -e "\(safePath)" ]; then
            chflags nouchg "\(safePath)"
            chmod +x "\(safePath)"
            rm "\(safePath)"
        fi
        """
    }.joined(separator: "\n")

    let appleScript = """
    do shell script "\(script.replacingOccurrences(of: "\"", with: "\\\""))" with administrator privileges
    """

    let task = Process()
    task.launchPath = "/usr/bin/osascript"
    task.arguments = ["-e", appleScript]

    task.terminationHandler = { process in
        DispatchQueue.main.async {
            completion(process.terminationStatus == 0)
        }
    }

    do {
        try task.run()
    } catch {
        completion(false)
    }
}

