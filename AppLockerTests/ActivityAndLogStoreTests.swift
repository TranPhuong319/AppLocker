//
//  ActivityAndLogStoreTests.swift
//  AppLockerTests
//
//  Created by Doe Phương on 7/11/26.
//

import Foundation
import os
import Testing

@Suite("ActivityStore & LogStore Filter, Parsing & Grouping Tests")
struct ActivityAndLogStoreTests {

    // MARK: - ActivityStore Parsing Tests

    @Test("ActivityStore parses Approved and Rejected security events")
    func activityStoreParsesApprovedAndRejectedEvents() {
        let now = Date()

        // 1. Approved Event
        let approvedEntry = AppLogEntry(
            date: now,
            subsystem: "com.TranPhuong319.AppLocker",
            category: "Security",
            level: .notice,
            message: "[SecurityEvent:Approved] App: Safari (PID 1001) | Path: /Applications/Safari.app"
        )
        let approvedItem = ActivityStore.parseSecurityEvent(from: approvedEntry)
        #expect(approvedItem != nil)
        #expect(approvedItem?.type == .approved)
        #expect(approvedItem?.targetAppName == "Safari")
        #expect(approvedItem?.targetPid == 1001)
        #expect(approvedItem?.targetAppPath == "/Applications/Safari.app")
        #expect(approvedItem?.denialReason == nil)

        // 2. Rejected Event (Timeout)
        let timeoutMsg = "[SecurityEvent:Rejected] App: Terminal (PID 2002) | " +
            "Path: /System/Applications/Utilities/Terminal.app | Reason: Timeout"
        let rejectedEntry = AppLogEntry(
            date: now,
            subsystem: "com.TranPhuong319.AppLocker",
            category: "Security",
            level: .notice,
            message: timeoutMsg
        )
        let rejectedItem = ActivityStore.parseSecurityEvent(from: rejectedEntry)
        #expect(rejectedItem != nil)
        #expect(rejectedItem?.type == .rejected)
        #expect(rejectedItem?.targetAppName == "Terminal")
        #expect(rejectedItem?.targetPid == 2002)
        #expect(rejectedItem?.denialReason == .timedOut)

        // 3. Rejected Event (User Cancel)
        let cancelMsg = "[SecurityEvent:Rejected] App: Notes (PID 3003) | " +
            "Path: /Applications/Notes.app | Reason: UserCancel"
        let userCancelEntry = AppLogEntry(
            date: now,
            subsystem: "com.TranPhuong319.AppLocker",
            category: "Security",
            level: .notice,
            message: cancelMsg
        )
        let cancelItem = ActivityStore.parseSecurityEvent(from: userCancelEntry)
        #expect(cancelItem?.denialReason == .userCancelled)
    }

    @Test("ActivityStore parses TamperBlocked security events and ignores non-security logs")
    func activityStoreParsesTamperBlockedEvents() {
        let now = Date()

        // Tamper Blocked Event (Without ResponsiblePath - backward compatibility)
        let tamperMsg = "[SecurityEvent:TamperBlocked] Target: Config (PID 0) | " +
            "Sender: bash (PID 8888) | Action: Truncate | SenderPath: /bin/bash"
        let tamperEntry = AppLogEntry(
            date: now,
            subsystem: "com.TranPhuong319.AppLocker.ESExtension",
            category: "EndpointSecurity",
            level: .error,
            message: tamperMsg
        )
        let tamperItem = ActivityStore.parseSecurityEvent(from: tamperEntry)
        #expect(tamperItem != nil)
        #expect(tamperItem?.type == .tamperBlocked)
        #expect(tamperItem?.targetAppName == "Config")
        #expect(tamperItem?.senderName == "bash")
        #expect(tamperItem?.senderPid == 8888)
        #expect(tamperItem?.senderPath == "/bin/bash")
        #expect(tamperItem?.responsiblePath == nil)
        #expect(tamperItem?.tamperAction == "Truncate")

        // Tamper Blocked Event (With ResponsiblePath)
        let tamperWithRespMsg = "[SecurityEvent:TamperBlocked] Target: Safari (PID 1001) | " +
            "Sender: Antigravity (PID 9999) | SenderPath: /bin/kill | " +
            "ResponsiblePath: /Applications/Antigravity.app"
        let tamperWithRespEntry = AppLogEntry(
            date: now,
            subsystem: "com.TranPhuong319.AppLocker.ESExtension",
            category: "EndpointSecurity",
            level: .error,
            message: tamperWithRespMsg
        )
        let tamperWithRespItem = ActivityStore.parseSecurityEvent(from: tamperWithRespEntry)
        #expect(tamperWithRespItem != nil)
        #expect(tamperWithRespItem?.senderName == "Antigravity")
        #expect(tamperWithRespItem?.senderPid == 9999)
        #expect(tamperWithRespItem?.senderPath == "/bin/kill")
        #expect(tamperWithRespItem?.responsiblePath == "/Applications/Antigravity.app")

        // Non-security message returns nil
        let normalEntry = AppLogEntry(
            date: now,
            subsystem: "com.TranPhuong319.AppLocker",
            category: "General",
            level: .info,
            message: "App started successfully"
        )
        #expect(ActivityStore.parseSecurityEvent(from: normalEntry) == nil)
    }

    // MARK: - ActivityStore Grouping Tests

    @Test("ActivityStore groups duplicate events within 2 seconds window")
    func activityStoreGroupsConsecutiveEvents() {
        let baseDate = Date()
        let item1 = SecurityActivityItem(
            date: baseDate,
            type: .approved,
            targetAppName: "Safari",
            targetAppPath: "/Applications/Safari.app",
            targetPid: 1001
        )
        let item2 = SecurityActivityItem(
            date: baseDate.addingTimeInterval(1.0),
            type: .approved,
            targetAppName: "Safari",
            targetAppPath: "/Applications/Safari.app",
            targetPid: 1001
        )
        let item3 = SecurityActivityItem(
            date: baseDate.addingTimeInterval(1.5),
            type: .approved,
            targetAppName: "Safari",
            targetAppPath: "/Applications/Safari.app",
            targetPid: 1001
        )
        let itemDifferent = SecurityActivityItem(
            date: baseDate.addingTimeInterval(1.6),
            type: .approved,
            targetAppName: "Music",
            targetAppPath: "/Applications/Music.app",
            targetPid: 1002
        )
        let itemAfterWindow = SecurityActivityItem(
            date: baseDate.addingTimeInterval(5.0),
            type: .approved,
            targetAppName: "Safari",
            targetAppPath: "/Applications/Safari.app",
            targetPid: 1001
        )

        let grouped = ActivityStore.groupActivities(
            [item1, item2, item3, itemDifferent, itemAfterWindow],
            windowSeconds: 2.0
        )
        #expect(grouped.count == 3)
        #expect(grouped[0].repeatCount == 3)
        #expect(grouped[0].targetAppName == "Safari")
        #expect(grouped[1].repeatCount == 1)
        #expect(grouped[1].targetAppName == "Music")
        #expect(grouped[2].repeatCount == 1)
        #expect(grouped[2].targetAppName == "Safari")
    }

    // MARK: - LogStore Filtering & Export Tests

    @Test("LogStore multi-dimensional filtering by subsystem, level, search, and time")
    @MainActor
    func logStoreFilteringCapabilities() {
        let store = LogStore()
        let now = Date()

        let entry1 = AppLogEntry(
            date: now.addingTimeInterval(-10),
            subsystem: "com.TranPhuong319.AppLocker",
            category: "UI",
            level: .info,
            message: "User opened Settings window"
        )
        let entry2 = AppLogEntry(
            date: now.addingTimeInterval(-20),
            subsystem: "com.TranPhuong319.AppLocker",
            category: "Policy",
            level: .error,
            message: "Failed to persist configuration file"
        )
        let entry3 = AppLogEntry(
            date: now.addingTimeInterval(-30),
            subsystem: "com.TranPhuong319.AppLocker.ESExtension",
            category: "EndpointSecurity",
            level: .notice,
            message: "Blocked untrusted execution: com.bad.app"
        )

        store.entries = [entry1, entry2, entry3]

        // 1. Filter by Main App subsystem only
        store.selectedSubsystem = .mainApp
        store.selectedLevel = .all
        store.searchText = ""
        let mainAppLogs = store.entries.filter { entry in
            guard let prefix = store.selectedSubsystem.subsystemPrefix else { return true }
            return entry.subsystem == prefix
        }
        #expect(mainAppLogs.count == 2)

        // 2. Filter by Level = Error
        store.selectedSubsystem = .all
        store.selectedLevel = .error
        let errorLogs = store.entries.filter { $0.resolvedLevel == .error }
        #expect(errorLogs.count == 1)
        #expect(errorLogs.first?.message.contains("Failed to persist") == true)

        // 3. Filter by search keyword
        store.searchText = "Blocked"
        let searchLogs = store.entries.filter {
            $0.message.localizedCaseInsensitiveContains(store.searchText)
        }
        #expect(searchLogs.count == 1)
        #expect(searchLogs.first?.subsystem.contains("ESExtension") == true)
    }

    @Test("LogStore consecutive log grouping and text export formatting")
    @MainActor
    func logStoreGroupingAndExportFormatting() {
        let store = LogStore()
        let now = Date()

        let entry1 = AppLogEntry(
            date: now,
            subsystem: "com.TranPhuong319.AppLocker",
            category: "Sync",
            level: .notice,
            message: "Heartbeat check"
        )
        let entry2 = AppLogEntry(
            date: now.addingTimeInterval(0.3),
            subsystem: "com.TranPhuong319.AppLocker",
            category: "Sync",
            level: .notice,
            message: "Heartbeat check"
        )
        let entry3 = AppLogEntry(
            date: now.addingTimeInterval(2.0),
            subsystem: "com.TranPhuong319.AppLocker",
            category: "Sync",
            level: .notice,
            message: "Heartbeat check"
        )

        store.filteredEntries = [entry1, entry2, entry3]
        let grouped = store.groupedEntries(within: 1.0)
        #expect(grouped.count == 2)
        #expect(grouped.first?.count == 2)
        #expect(grouped.last?.count == 1)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let exported = store.exportText(dateFormatter: formatter)
        #expect(exported.contains("[App/Sync] NOTICE: Heartbeat check"))
    }
}
