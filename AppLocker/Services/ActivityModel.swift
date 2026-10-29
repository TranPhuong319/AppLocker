//
//  ActivityModel.swift
//  AppLocker
//
//  Created by Doe Phương on 27/10/26.
//

import Foundation
import SwiftUI

// MARK: - Security Event Type

public enum SecurityEventType: String, Sendable, CaseIterable, Identifiable {
    case approved = "Approved"
    case rejected = "Rejected"
    case tamperBlocked = "Tamper"

    public var id: String { rawValue }

    public var symbol: String {
        switch self {
        case .approved:
            return "checkmark.circle.fill"
        case .rejected:
            return "hand.raised.fill"
        case .tamperBlocked:
            return "exclamationmark.shield.fill"
        }
    }

    public var symbolColor: Color {
        switch self {
        case .approved:
            return .green
        case .rejected:
            return .orange
        case .tamperBlocked:
            return .red
        }
    }

    public var titleKey: LocalizedStringKey {
        switch self {
        case .approved:
            return "Allowed Launch: %@"
        case .rejected:
            return "Access Denied: %@"
        case .tamperBlocked:
            return "Anti-Tamper Shield: %@"
        }
    }
}

// MARK: - Denial Reason

public enum DenialReason: String, Sendable, CaseIterable {
    case userCancelled = "UserCancel"
    case timedOut = "Timeout"

    public var localizedDescription: String {
        switch self {
        case .userCancelled:
            return String(localized: "Cancelled by User")
        case .timedOut:
            return String(localized: "Timed Out")
        }
    }
}

// MARK: - Security Activity Item

public struct SecurityActivityItem: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let date: Date
    public let type: SecurityEventType
    public let targetAppName: String
    public let targetAppPath: String?
    public let targetPid: Int32
    public let denialReason: DenialReason?
    public let senderName: String?
    public let senderPid: Int32?
    public let senderPath: String?
    public let tamperAction: String?
    public var repeatCount: Int

    public init(
        id: UUID = UUID(),
        date: Date,
        type: SecurityEventType,
        targetAppName: String,
        targetAppPath: String? = nil,
        targetPid: Int32,
        denialReason: DenialReason? = nil,
        senderName: String? = nil,
        senderPid: Int32? = nil,
        senderPath: String? = nil,
        tamperAction: String? = nil,
        repeatCount: Int = 1
    ) {
        self.id = id
        self.date = date
        self.type = type
        self.targetAppName = targetAppName
        self.targetAppPath = targetAppPath
        self.targetPid = targetPid
        self.denialReason = denialReason
        self.senderName = senderName
        self.senderPid = senderPid
        self.senderPath = senderPath
        self.tamperAction = tamperAction
        self.repeatCount = repeatCount
    }

    public func clipboardFormattedText(dateFormatter: DateFormatter) -> String {
        var lines: [String] = []
        lines.append("[AppLocker Security Activity]")
        lines.append("Type: \(type.rawValue)")
        if let reason = denialReason {
            lines.append("Reason: \(reason == .timedOut ? "Timed Out" : "Cancelled by User")")
        }
        lines.append("Target App: \(targetAppName) (PID: \(targetPid))")
        if let path = targetAppPath, !path.isEmpty {
            lines.append("Target Path: \(path)")
        }
        if let sender = senderName {
            let pidStr = senderPid.map { " (PID: \($0))" } ?? ""
            lines.append("Sender: \(sender)\(pidStr)")
        }
        if let sPath = senderPath, !sPath.isEmpty {
            lines.append("Sender Path: \(sPath)")
        }
        if let action = tamperAction, !action.isEmpty {
            lines.append("Action: \(action)")
        }
        lines.append("Time: \(dateFormatter.string(from: date))")
        if repeatCount > 1 {
            lines.append("Consecutive Attempts: \(repeatCount)")
        }
        return lines.joined(separator: "\n")
    }
}
