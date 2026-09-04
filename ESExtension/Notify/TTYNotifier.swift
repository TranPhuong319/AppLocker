//
//  TTYNotifier.swift
//  AppLocker
//
//  Created by Doe Phương on 29/12/25.
//

import Darwin
import Foundation

final class TTYNotifier {
    // Find the process name of a process ID.
    private static func processName(for processID: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 256)
        let length = proc_name(processID, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return buffer.withUnsafeBufferPointer { pointer in
            pointer.baseAddress.map { String(cString: $0) }
        }
    }

    // Find the TTY path of a process (e.g., /dev/ttys001).
    static func getTTYPath(for processID: pid_t) -> String? {
        let bufferSize = proc_pidinfo(processID, PROC_PIDLISTFDS, 0, nil, 0)
        guard bufferSize > 0 else { return nil }

        let fdInfoSize = MemoryLayout<proc_fdinfo>.stride
        let numFDs = Int(bufferSize) / fdInfoSize
        var fdInfos = [proc_fdinfo](repeating: proc_fdinfo(), count: numFDs)

        let result = proc_pidinfo(processID, PROC_PIDLISTFDS, 0, &fdInfos, bufferSize)
        guard result > 0 else { return nil }

        for fileDescriptorInfo in fdInfos where fileDescriptorInfo.proc_fdtype == PROX_FDTYPE_VNODE {
                var vnodeInfo = vnode_fdinfowithpath()
                let infoSize = Int32(MemoryLayout<vnode_fdinfowithpath>.stride)

                let bytesReturned = proc_pidfdinfo(
                    processID,
                    fileDescriptorInfo.proc_fd,
                    PROC_PIDFDVNODEPATHINFO,
                    &vnodeInfo,
                    infoSize
                )

                if bytesReturned > 0 {
                    let path = withUnsafePointer(to: &vnodeInfo.pvip.vip_path) { pointer in
                        pointer.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { cStringPointer in
                            String(cString: cStringPointer)
                        }
                    }

                    if path.hasPrefix("/dev/tty") {
                        return path
                    }
                }
        }
        return nil
    }

    // Write a colored block message to the parent's TTY when execution is denied.
    static func notify(
        targetPid: pid_t,
        parentPid: pid_t,
        blockedPath: String,
        cdhash: String,
        identifier: String? = nil
    ) {
        guard let ttyPath = getTTYPath(for: parentPid) else { return }
        guard let fileHandle = FileHandle(forWritingAtPath: ttyPath) else { return }
        defer { try? fileHandle.close() }

        let title        = "AppLocker"
        let description  = String(localized:
        """
        The following application has been blocked from execution
        because it was added to the locked list.
        """)

        let labelPath    = String(localized: "Path:")
        let labelId      = String(localized: "Identifier:")
        let labelCDHash  = String(localized: "CDHash:")
        let labelPid     = String(localized: "PID:")
        let labelParent  = String(localized: "Parent:")
        let labelAuth    = String(localized: "Authenticate...")

        let boldRed = "\u{001B}[1m\u{001B}[31m"
        let reset   = "\u{001B}[0m"
        let bold    = "\u{001B}[1m"

        let paddedPath   = labelPath.padding(toLength: 15, withPad: " ", startingAt: 0)
        let paddedId     = labelId.padding(toLength: 15, withPad: " ", startingAt: 0)
        let paddedCDHash = labelCDHash.padding(toLength: 15, withPad: " ", startingAt: 0)
        let paddedPid    = labelPid.padding(toLength: 15, withPad: " ", startingAt: 0)
        let paddedParent = labelParent.padding(toLength: 15, withPad: " ", startingAt: 0)

        let parentName = processName(for: parentPid)
        let parentDisplay = parentName.map { "\($0) (PID: \(parentPid))" } ?? "\(parentPid)"

        let message = """
            \n
            \(boldRed)\(title)\(reset)

            \(description)

            \(bold)\(paddedPath)\(reset) \(blockedPath)
            \(bold)\(paddedId)\(reset) \(identifier ?? "Unknown")
            \(bold)\(paddedCDHash)\(reset) \(cdhash)
            \(bold)\(paddedPid)\(reset) \(targetPid)
            \(bold)\(paddedParent)\(reset) \(parentDisplay)
            \(labelAuth)
            \n
            """

        if let data = message.data(using: .utf8) {
            fileHandle.write(data)
        }
    }
}
