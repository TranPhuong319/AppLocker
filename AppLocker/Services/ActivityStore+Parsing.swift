//
//  ActivityStore+Parsing.swift
//  AppLocker
//
//  Created by Doe Phương on 31/10/26.
//

import Foundation

// MARK: - Event Parsing & Grouping Heuristics

extension ActivityStore {

    nonisolated static func groupActivities(
        _ items: [SecurityActivityItem],
        windowSeconds: TimeInterval = 30.0
    ) -> [SecurityActivityItem] {
        guard !items.isEmpty else { return [] }
        var result: [SecurityActivityItem] = []
        var current = items[0]

        for item in items.dropFirst() {
            let isSameTarget = item.targetAppName == current.targetAppName
            let isSameType = item.type == current.type
            let isSameReason = item.denialReason == current.denialReason
            let isSameAction = item.tamperAction == current.tamperAction
            let isWithinWindow = abs(item.date.timeIntervalSince(current.date)) <= windowSeconds

            if isSameTarget && isSameType && isSameReason && isSameAction && isWithinWindow {
                current.repeatCount += item.repeatCount
            } else {
                result.append(current)
                current = item
            }
        }
        result.append(current)
        return result
    }

    nonisolated static func parseSecurityEvent(from entry: AppLogEntry) -> SecurityActivityItem? {
        let msg = entry.message
        if msg.contains("[SecurityEvent:Approved]") {
            return parseSimpleSecurityEvent(type: .approved, message: msg, date: entry.date)
        } else if msg.contains("[SecurityEvent:Rejected]") {
            return parseSimpleSecurityEvent(type: .rejected, message: msg, date: entry.date)
        } else if msg.contains("[SecurityEvent:TamperBlocked]") {
            return parseTamperSecurityEvent(message: msg, date: entry.date)
        }
        return nil
    }

    // MARK: - Private Parser Helpers

    nonisolated private static func parseSimpleSecurityEvent(
        type: SecurityEventType,
        message: String,
        date: Date
    ) -> SecurityActivityItem? {
        guard let targetRaw = extractField(from: message, prefix: "App: ", delimiter: " | Path: ")
                ?? extractField(from: message, prefix: "App: ", delimiter: nil) else { return nil }

        let (appName, pid) = parseProcessInfo(from: targetRaw)
        guard let appName, let pid else { return nil }

        let path = extractField(from: message, prefix: " | Path: ", delimiter: " | Reason: ")
            ?? extractField(from: message, prefix: " | Path: ", delimiter: nil)

        let denialReason: DenialReason? = if type == .rejected {
            if message.contains("Reason: \(AuthDecisionReason.timeout.rawValue)") {
                .timedOut
            } else if message.contains("Reason: \(AuthDecisionReason.userCancel.rawValue)") {
                .userCancelled
            } else {
                nil
            }
        } else {
            nil
        }

        return SecurityActivityItem(
            date: date,
            type: type,
            targetAppName: appName,
            targetAppPath: path,
            targetPid: pid,
            denialReason: denialReason
        )
    }

    nonisolated private static func parseTamperSecurityEvent(message: String, date: Date) -> SecurityActivityItem? {
        guard let targetRaw = extractField(from: message, prefix: "Target: ") else { return nil }
        let (targetName, targetPid) = parseProcessInfo(from: targetRaw)
        guard let targetName, let targetPid else { return nil }

        let senderRaw = extractField(from: message, prefix: " | Sender: ")
        let (senderName, senderPid) = parseProcessInfo(from: senderRaw)
        let senderPath = extractField(from: message, prefix: " | SenderPath: ", delimiter: nil)
        let tamperAction = extractField(from: message, prefix: " | Action: ")

        return SecurityActivityItem(
            date: date,
            type: .tamperBlocked,
            targetAppName: targetName,
            targetPid: targetPid,
            senderName: senderName,
            senderPid: senderPid,
            senderPath: senderPath,
            tamperAction: tamperAction
        )
    }

    nonisolated private static func extractField(
        from message: String,
        prefix: String,
        delimiter: String? = " | "
    ) -> String? {
        guard let range = message.range(of: prefix) else { return nil }
        let after = message[range.upperBound...]
        if let delimiter, let delimRange = after.range(of: delimiter) {
            return String(after[..<delimRange.lowerBound]).trimmingCharacters(in: .whitespaces)
        }
        return String(after).trimmingCharacters(in: .whitespaces)
    }

    nonisolated private static func parseProcessInfo(from raw: String?) -> (name: String?, pid: Int32?) {
        guard let raw else { return (nil, nil) }
        guard let open = raw.range(of: " (PID "), raw.hasSuffix(")") else {
            return (raw.trimmingCharacters(in: .whitespaces), nil)
        }
        let name = String(raw[..<open.lowerBound]).trimmingCharacters(in: .whitespaces)
        let pidText = raw[open.upperBound...].dropLast()
        return (name, Int32(pidText))
    }
}
