# Graph Report - AppLocker  (2026-10-03)

## Corpus Check
- 46 files · ~279,312 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 1473 nodes · 2680 edges · 129 communities (75 shown, 54 thin omitted)
- Extraction: 94% EXTRACTED · 6% INFERRED · 0% AMBIGUOUS · INFERRED: 170 edges (avg confidence: 0.83)
- Token cost: 0 input · 0 output

## Community Hubs (Navigation)
- About & System Diagnostics
- Log Management & Filtering
- XPC Inter-Process Communication
- .bottomActionBar
- About & System Diagnostics
- Authentication & Security Lock
- XPC Inter-Process Communication
- EndpointSecurity Engine
- Authentication & Security Lock
- check-prerequisites.sh
- About & System Diagnostics
- Log Management & Filtering
- Architecture Rules & Guidelines
- EndpointSecurity Engine
- App Lifecycle & Application Delegate
- Log Management & Filtering
- EndpointSecurity Engine
- About & System Diagnostics
- Log Management & Filtering
- Log Management & Filtering
- es_event_exec_t
- Authentication & Security Lock
- argparse
- macOS TouchBar Integration
- App Lifecycle & Application Delegate
- App Lifecycle & Application Delegate
- App Icon & Asset Pipeline
- Authentication & Security Lock
- MainUIButtons.swift
- ContentView.swift
- Preferences & Settings Interface
- ESExtension Endpoint Security 
- Preferences & Settings Interface
- Preferences & Settings Interface
- EndpointSecurity Engine
- App Lifecycle & Application Delegate
- App Lifecycle & Application Delegate
- Log Management & Filtering
- About & System Diagnostics
- macOS TouchBar Integration
- Log Management & Filtering
- Preferences & Settings Interface
- Window Layout & Management
- Window Layout & Management
- Log Management & Filtering
- Log Management & Filtering
- .listener()
- Window Layout & Management
- macOS TouchBar Integration
- macOS TouchBar Integration
- SectionHeader.swift
- AppLocker/Bridging-Header.h
- HotKeyManager.swift
- ESAppProtocol.swift
- App Lifecycle & Application Delegate
- Log Management & Filtering
- Speckit Implement Skill
- AddAppSheet.swift
- Preferences & Settings Interface
- Preferences & Settings Interface
- Preferences & Settings Interface
- App Lifecycle & Application Delegate
- CallServiceObserver
- Data
- Log Management & Filtering
- AppRowButtonStyle.swift
- Log Management & Filtering
- WelcomeView.swift
- S
- Authentication & Security Lock
- MissingAppsSheet.swift
- Log Management & Filtering
- App Lifecycle & Application Delegate
- App Lifecycle & Application Delegate
- TouchBarType
- pid_t
- XPC Inter-Process Communication
- App Lifecycle & Application Delegate
- .panel()
- AUTH_EXEC PID Assignment
- Speckit Checklist Skill
- License (English)
- AppLocker AppIcon Assets
- AppLocker Usage Guide (EN)
- Conventional Commit Style
- English Base Localization
- Speckit Analyze Skill
- Speckit Clarify Skill
- Speckit Constitution Skill
- Speckit Converge Skill
- Speckit Tasks To Issues
- Bug Report Issue Template
- Feature Request Issue Template
- GitHub Issue Template Config
- Pull Request Template
- GitHub CI/CD Workflow
- AppLocker App Icon SVG
- Context
- Sendable
- String
- Bool
- AppIcon icon_128x128@2x.png
- AppIcon icon_128x128.png
- AppIcon icon_16x16@2x.png
- AppIcon icon_16x16.png
- AppIcon icon_256x256@2x.png
- AppIcon icon_256x256.png
- AppIcon icon_32x32@2x.png
- AppIcon icon_32x32.png
- AppIcon icon_512x512.png
- Color
- Content
- App Icon & Asset Pipeline
- Menu Bar Quick Access Screensh
- NSXPCListener
- uid_t
- UnsafePointer
- Int
- Never
- NSCoder
- Security Policy
- Uninstall Fix Requirements Che
- Fix Uninstall/Reset Flow Spec
- Numeric Transition Requirement
- Native Numeric Transition Spec
- Task
- TimeInterval
- UInt64
- UUID

## God Nodes (most connected - your core abstractions)
1. `ESManager` - 105 edges
2. `AppState` - 74 edges
3. `AppDelegate` - 69 edges
4. `LogsSettingsTab` - 46 edges
5. `Logfile` - 42 edges
6. `AppUpdater` - 32 edges
7. `XPCServer` - 31 edges
8. `AboutView` - 27 edges
9. `LogStore` - 26 edges
10. `SettingsTab` - 24 edges

## Surprising Connections (you probably didn't know these)
- `AppLocker Demo Animation` --conceptually_related_to--> `AppLocker Project Overview`  [INFERRED]
  docs/gif/demo.gif → README.md
- `Kernel-Level Process Interception` --semantically_similar_to--> `Process Interception Flow (SIGSTOP/SIGCONT)`  [INFERRED] [semantically similar]
  README.md → .spec/existing-architecture.md
- `Main Dashboard Screenshot` --conceptually_related_to--> `AppLocker Main Application`  [INFERRED]
  docs/images/screenshots/screenshot-main.png → .spec/existing-architecture.md
- `Touch ID Auth Dialog Screenshot` --conceptually_related_to--> `Batch Authentication Flow`  [INFERRED]
  docs/images/screenshots/screenshot-auth.png → README.md
- `Batch Auth Multi-App Screenshot` --conceptually_related_to--> `Batch Authentication Flow`  [INFERRED]
  docs/images/screenshots/screenshot-mutiple-auth.png → README.md

## Import Cycles
- None detected.

## Hyperedges (group relationships)
- **Endpoint Security Event Flow** — _agents_rules_endpoint_security_auth_exec, _agents_rules_endpoint_security_notify_exec, _agents_rules_endpoint_security_posix_liveness [EXTRACTED 1.00]
- **Feature 001 Full Artifact Set** — specs_001_migrate_observable_spec, specs_001_migrate_observable_plan, specs_001_tasks, specs_001_research, specs_001_data_model, specs_001_quickstart, specs_001_contracts_state_protocols, specs_001_checklists_requirements [EXTRACTED 1.00]
- **AppLocker Three-Layer Architecture** — _spec_existing_architecture_main_application, _spec_existing_architecture_es_extension, _spec_existing_architecture_shared_core [EXTRACTED 1.00]
- **Active Feature Specifications** — specs_001_migrate_observable_spec, specs_002_separate_user_configs_spec, specs_003_fix_uninstall_spec, specs_005_native_numeric_spec, specs_006_liquid_glass_spec [INFERRED 0.90]
- **AppLocker UI Surfaces** — docs_images_screenshots_main, docs_images_screenshots_auth, docs_images_screenshots_menubar, docs_images_screenshots_batch [INFERRED 0.90]
- **GitHub Contribution Workflow** — _github_issue_bug_report, _github_issue_feature, _github_pr_template, _github_workflows_main_ci [INFERRED 0.90]
- **Security Core (Crypto + XPC + Anti-Tamper)** — _spec_existing_architecture_mutual_ecdsa, readme_anti_tampering, _agents_rules_xpc_and_security_xpc_reconnect, _agents_rules_architecture_cryptokit [INFERRED 0.90]
- **Speckit Template System** — _specify_templates_spec, _specify_templates_plan, _specify_templates_tasks, _specify_templates_checklist, _specify_templates_constitution [INFERRED 0.90]

## Communities (129 total, 54 thin omitted)

### Community 0 - "About & System Diagnostics"
Cohesion: 0.06
Nodes (37): AnyObject, .actionsSection, Void, AppUpdater, .automaticallyChecksForUpdates, .automaticallyDownloadsUpdates, .currentChannel, .downloadState (+29 more)

### Community 1 - "Log Management & Filtering"
Cohesion: 0.06
Nodes (40): LogEntryRow, .body, .categoryBadge, .copyIcon, .levelColor, .levelDot, .repeatBadge, .subsystemBadge (+32 more)

### Community 2 - "XPC Inter-Process Communication"
Cohesion: 0.07
Nodes (31): BatchAuthWindowController, .isWindowVisible, Bool, NSCoder, NSWindow, BatchAppRowView, .body, BatchAuthView (+23 more)

### Community 3 - ".bottomActionBar"
Cohesion: 0.07
Nodes (21): .bottomActionBar, .bottomActionBar, .bottomActionBar, NSWindow, AppState, .searchTextLockApps, .searchTextUnlockableApps, .systemUnlockableApps (+13 more)

### Community 4 - "About & System Diagnostics"
Cohesion: 0.09
Nodes (24): .body, DragHostingView, EqualWidthKey, LiquidGlassBackgroundModifier, LiquidGlassBarModifier, LiquidGlassCapsuleModifier, LiquidGlassCardModifier, LiquidGlassCircleModifier (+16 more)

### Community 5 - "Authentication & Security Lock"
Cohesion: 0.06
Nodes (21): MockLockManager, Bool, Int, Set, Notification, LockManagerProtocol, Bool, Int (+13 more)

### Community 6 - "XPC Inter-Process Communication"
Cohesion: 0.10
Nodes (19): ESXPCClient, Bool, Int, Int32, NSXPCConnection, String, Action, install (+11 more)

### Community 7 - "EndpointSecurity Engine"
Cohesion: 0.08
Nodes (24): DispatchSourceFileSystemObject, DispatchSourceTimer, es_process_t, audit_token_t, pid_t, Bool, Int32, Void (+16 more)

### Community 8 - "Authentication & Security Lock"
Cohesion: 0.09
Nodes (24): ConfigLoadResult, ConfigStore, .configURL, .userDirectoryURL, Bool, Int, URL, Codable (+16 more)

### Community 9 - "check-prerequisites.sh"
Cohesion: 0.13
Nodes (29): check-prerequisites.sh script, check_dir(), check_file(), find_specify_root(), format_speckit_command(), get_current_branch(), get_feature_paths(), get_invoke_separator() (+21 more)

### Community 10 - "About & System Diagnostics"
Cohesion: 0.07
Nodes (28): AboutView, .appIdentitySection, .architectureBadgesSection, .architectureButton, .architectureName, .copyVersionIcon, .footerSection, .isExtensionActive (+20 more)

### Community 11 - "Log Management & Filtering"
Cohesion: 0.10
Nodes (14): Equatable, OpaquePointer, LoadedConfigs, Bool, Set, uid_t, NSXPCConnection, XPCConn (+6 more)

### Community 12 - "Architecture Rules & Guidelines"
Cohesion: 0.07
Nodes (31): AppLocker Agent Rules, AppIconProvider NSCache, Clean Architecture & Platform API Rules, CryptoKit ECDSA Auth, YAGNI (You Aren't Gonna Need It), @MainActor UI Isolation, Swift Concurrency Rules, Apple Unified Logging (os.Logger) (+23 more)

### Community 13 - "EndpointSecurity Engine"
Cohesion: 0.19
Nodes (11): es_auth_result_t, es_event_rename_t, Bool, ESMessage, Int32, OpaquePointer, String, ESSafetyValve (+3 more)

### Community 14 - "App Lifecycle & Application Delegate"
Cohesion: 0.09
Nodes (14): .isAgentActive, .isLaunchedByLaunchd, Bool, AppDelegate, String, NSImageView, Notification.Name, HotKeyManager (+6 more)

### Community 15 - "Log Management & Filtering"
Cohesion: 0.09
Nodes (26): AnyShapeStyle, LogsSettingsTab, .logListContent, .clearIcon, .copyStatusIcon, .dragSelectionOverlay, .emptyPlaceholder, .exportFilename (+18 more)

### Community 16 - "EndpointSecurity Engine"
Cohesion: 0.15
Nodes (11): DispatchQueue, es_event_type_t, UInt64, ESAuthorizer, ESClientObject, ESTamper, Bool, ESMessage (+3 more)

### Community 17 - "About & System Diagnostics"
Cohesion: 0.15
Nodes (7): Combine, Darwin, EndpointSecurity, Foundation, os, Security, SystemConfiguration

### Community 18 - "Log Management & Filtering"
Cohesion: 0.12
Nodes (16): LogSelectionManager, .hasSelection, .selectedCount, Bool, CGPoint, CGRect, DateFormatter, Int (+8 more)

### Community 19 - "Log Management & Filtering"
Cohesion: 0.12
Nodes (7): AppKit, Notification.Name, Observation, OSLog, SwiftUI, SystemExtensions, UniformTypeIdentifiers

### Community 20 - "es_event_exec_t"
Cohesion: 0.14
Nodes (16): es_event_exec_t, es_file_t, es_message_t, es_string_token_t, OpaquePointer, ESMessage, .pointee, OpaquePointer (+8 more)

### Community 21 - "Authentication & Security Lock"
Cohesion: 0.17
Nodes (14): LockingPopupSheet, .body, AppearanceSettingsTab, .body, Bool, ThemeThumbnailView, .body, .bottomWindowLayer (+6 more)

### Community 22 - "argparse"
Cohesion: 0.14
Nodes (19): argparse, collections, get_lang_name(), main(), write_stats(), generate_html(), generate_markdown(), get_commits() (+11 more)

### Community 23 - "macOS TouchBar Integration"
Cohesion: 0.16
Nodes (9): AnyObject, NSButton, Notification, NSTouchBarItem, NSWindow, TouchBarManager, NSTouchBar, NSTouchBarDelegate (+1 more)

### Community 24 - "App Lifecycle & Application Delegate"
Cohesion: 0.13
Nodes (12): NSApplication, .appDelegate, URL, Bool, NSAlert, AlertResult, button, cancelled (+4 more)

### Community 25 - "App Lifecycle & Application Delegate"
Cohesion: 0.11
Nodes (15): AgentManageResult, alreadyInstalled, alreadyUninstalled, failed, installed, uninstalled, Error, String (+7 more)

### Community 26 - "App Icon & Asset Pipeline"
Cohesion: 0.16
Nodes (10): AppIconView, .body, Bool, CGFloat, NSImage, AppIconProvider, CGFloat, NSImage (+2 more)

### Community 27 - "Authentication & Security Lock"
Cohesion: 0.20
Nodes (8): LockES, Bool, InstalledApp, Int, LockedAppConfig, String, Void, LockManagerProtocol

### Community 28 - "MainUIButtons.swift"
Cohesion: 0.20
Nodes (13): AddAppRow, .body, .selectionIndicator, DeleteQueueRow, .body, LockedAppRow, .body, MissingAppRow (+5 more)

### Community 29 - "ContentView.swift"
Cohesion: 0.12
Nodes (13): ContentView, .body, .contentView, .deleteQueueNotificationBar, .emptyStateView, .mainListView, .missingAppsWarningButton, .scrollEdgeDissolveMask (+5 more)

### Community 30 - "Preferences & Settings Interface"
Cohesion: 0.16
Nodes (9): SettingsNavigator, .selectedTab, SettingsView, .body, .securityLockIcon, Bool, Int, Void (+1 more)

### Community 31 - "ESExtension Endpoint Security "
Cohesion: 0.14
Nodes (17): ESExtension Endpoint Security Daemon, Process Interception Flow (SIGSTOP/SIGCONT), AppLocker Main Application, Mutual ECDSA P-256 XPC Handshake, Shared Core Framework, AppLocker Demo Animation, Touch ID Auth Dialog Screenshot, Batch Auth Multi-App Screenshot (+9 more)

### Community 32 - "Preferences & Settings Interface"
Cohesion: 0.15
Nodes (8): GeneralSettingsTab, .body, Bool, Bool, UpdatesSettingsTab, .body, .currentVersionRow, .selectedChannel

### Community 33 - "Preferences & Settings Interface"
Cohesion: 0.19
Nodes (8): SecuritySettingsTab, .body, .lockedStateView, .unlockedContent, Bool, Int, Binding, Double

### Community 34 - "EndpointSecurity Engine"
Cohesion: 0.20
Nodes (7): OpaquePointer, audit_token_t, Bool, Int, Int32, pid_t, String

### Community 35 - "App Lifecycle & Application Delegate"
Cohesion: 0.13
Nodes (5): Bool, escaping, LAContext, LocalAuthentication, AuthenticationManager

### Community 36 - "App Lifecycle & Application Delegate"
Cohesion: 0.19
Nodes (7): SettingsWindowController, Bool, CGFloat, Notification, NSCoder, NSSize, NSWindow

### Community 37 - "Log Management & Filtering"
Cohesion: 0.19
Nodes (12): LogDragAutoScroller, .direction, .dragCurrentInContent, .dragStartInContent, .visibleContentBottom, .visibleContentTop, CGFloat, CGPoint (+4 more)

### Community 38 - "About & System Diagnostics"
Cohesion: 0.17
Nodes (6): AboutWindowController, NSCoder, Notification, WelcomeWindowController, NSWindowController, NSWindowDelegate

### Community 39 - "macOS TouchBar Integration"
Cohesion: 0.30
Nodes (5): MissingAppsTouchBarItem, NSCoder, NSTouchBarItem, NSButtonTouchBarItem, NSRect

### Community 40 - "Log Management & Filtering"
Cohesion: 0.21
Nodes (5): Int, ScrollViewProxy, .logList, Gesture, MainActor

### Community 41 - "Preferences & Settings Interface"
Cohesion: 0.17
Nodes (12): SettingsTab, appearance, .displayName, general, .iconName, .id, logs, .minSize (+4 more)

### Community 42 - "Window Layout & Management"
Cohesion: 0.21
Nodes (7): Coordinator, ScrollBottomTracker, Sendable, Void, NSObject, NSObjectProtocol, NSScrollView

### Community 43 - "Window Layout & Management"
Cohesion: 0.22
Nodes (6): AppListWindowController, Notification, NSCoder, NSViewController, NSWindow, NSHostingController

### Community 44 - "Log Management & Filtering"
Cohesion: 0.18
Nodes (11): LogLevelFilter, all, debug, .displayName, error, fault, .id, info (+3 more)

### Community 45 - "Log Management & Filtering"
Cohesion: 0.18
Nodes (11): LogTimeRange, all, currentSession, .displayName, .id, last24Hours, last6Hours, last7Days (+3 more)

### Community 46 - ".listener()"
Cohesion: 0.24
Nodes (8): Bool, NSXPCConnection, NSXPCListener, SecRequirement, CodeSignatureValidator, audit_token_t, Bool, NSXPCConnection

### Community 47 - "Window Layout & Management"
Cohesion: 0.27
Nodes (7): Bool, NSSize, NSViewController, NSWindow, WindowConfiguration, WindowManager, NSColor

### Community 48 - "macOS TouchBar Integration"
Cohesion: 0.22
Nodes (6): DeleteQueueTouchBarButton, .intrinsicContentSize, LockTouchBarButton, NSTouchBarItem.Identifier, NSSize, NSButton

### Community 49 - "macOS TouchBar Integration"
Cohesion: 0.29
Nodes (5): SearchTouchBarItem, Any, Notification, NSPopoverTouchBarItem, NSSearchFieldDelegate

### Community 50 - "SectionHeader.swift"
Cohesion: 0.22
Nodes (7): SectionHeader, .body, LocalizedStringKey, DeleteQueueSheet, .body, .topHeader, CGFloat

### Community 51 - "AppLocker/Bridging-Header.h"
Cohesion: 0.22
Nodes (8): audit_token_t, NSXPCConnection, audit_token_t, NSXPCConnection, libbsm, libproc, notify, proc_info

### Community 52 - "HotKeyManager.swift"
Cohesion: 0.24
Nodes (5): HotKeyManager, Carbon, Cocoa, EventHandlerRef, EventHotKeyRef

### Community 53 - "ESAppProtocol.swift"
Cohesion: 0.33
Nodes (4): ESAppProtocol, Bool, Int32, Void

### Community 54 - "App Lifecycle & Application Delegate"
Cohesion: 0.22
Nodes (5): MenuBarImageView, Notification.Name, NSImageView, NSPoint, Symbols

### Community 55 - "Log Management & Filtering"
Cohesion: 0.22
Nodes (9): LogSubsystemFilter, all, .displayName, esExtension, .id, mainApp, .subsystemPrefix, LocalizedStringKey (+1 more)

### Community 56 - "Speckit Implement Skill"
Cohesion: 0.25
Nodes (8): Speckit Implement Skill, Speckit Plan Skill, Speckit Specify Skill, Speckit Tasks Skill, Plan Template, Spec Template, Tasks Template, Speckit Workflow Configuration

### Community 57 - "AddAppSheet.swift"
Cohesion: 0.29
Nodes (6): AddAppSheet, .body, .lockButtonTitle, Bool, CGFloat, Void

### Community 58 - "Preferences & Settings Interface"
Cohesion: 0.25
Nodes (8): LocalizedStringKey, ThemeMode, dark, .displayName, .id, light, system, CaseIterable

### Community 59 - "Preferences & Settings Interface"
Cohesion: 0.25
Nodes (7): LocalizedStringKey, UpdateChannel, beta, .description, .displayName, .id, stable

### Community 60 - "Preferences & Settings Interface"
Cohesion: 0.32
Nodes (6): NSView, .enclosingSplitView, SidebarCollapsePreventer, Context, NSSplitView, NSViewRepresentable

### Community 61 - "App Lifecycle & Application Delegate"
Cohesion: 0.25
Nodes (3): Int32, Notification, String

### Community 62 - "CallServiceObserver"
Cohesion: 0.32
Nodes (3): CallServiceObserver, Bool, Int32

### Community 63 - "Data"
Cohesion: 0.43
Nodes (3): Data, Bool, uid_t

### Community 64 - "Log Management & Filtering"
Cohesion: 0.29
Nodes (5): LogSearchFocusModifier, Bool, Content, View, FocusState

### Community 65 - "AppRowButtonStyle.swift"
Cohesion: 0.33
Nodes (4): AppRowButtonStyle, View, ButtonStyle, Configuration

### Community 66 - "Log Management & Filtering"
Cohesion: 0.47
Nodes (4): LogRowBoundsPreference, CGRect, UUID, PreferenceKey

### Community 67 - "WelcomeView.swift"
Cohesion: 0.40
Nodes (4): Bool, WelcomeView, .body, .licenseText

### Community 68 - "S"
Cohesion: 0.33
Nodes (5): S, Sequence, fuzzyMatch(), Bool, String

### Community 69 - "Authentication & Security Lock"
Cohesion: 0.40
Nodes (5): PendingAppItem, Bool, Int32, Hashable, Identifiable

### Community 70 - "MissingAppsSheet.swift"
Cohesion: 0.40
Nodes (4): MissingAppsSheet, .missingPaths, .topHeader, CGFloat

### Community 71 - "Log Management & Filtering"
Cohesion: 0.40
Nodes (3): Int, ScrollViewProxy, View

### Community 74 - "TouchBarType"
Cohesion: 0.40
Nodes (5): TouchBarType, addAppPopup, deleteQueuePopup, mainWindow, missingAppsPopup

### Community 78 - ".panel()"
Cohesion: 0.50
Nodes (3): Any, Bool, URL

### Community 79 - "AUTH_EXEC PID Assignment"
Cohesion: 0.67
Nodes (3): AUTH_EXEC PID Assignment, NOTIFY_EXEC Pre/Post Exec Timing, POSIX Liveness & PID Recycling Defense

## Knowledge Gaps
- **239 isolated node(s):** `Notification.Name`, `NSTouchBarItem.Identifier`, `.isWindowVisible`, `.authButtonTitle`, `.bottomActionBar` (+234 more)
  These have ≤1 connection - possible missing edges or undocumented components. (Counts symbols only; 528 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **54 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `ESManager` connect `EndpointSecurity Engine` to `EndpointSecurity Engine`, `Window Layout & Management`, `Log Management & Filtering`, `EndpointSecurity Engine`, `.listener()`, `EndpointSecurity Engine`, `About & System Diagnostics`, `es_event_exec_t`, `ESAppProtocol.swift`, `Data`?**
  _High betweenness centrality (0.151) - this node is a cross-community bridge._
- **Why does `Foundation` connect `About & System Diagnostics` to `About & System Diagnostics`, `.bottomActionBar`, `About & System Diagnostics`, `Authentication & Security Lock`, `S`, `App Lifecycle & Application Delegate`, `Authentication & Security Lock`, `Log Management & Filtering`, `XPC Inter-Process Communication`, `Log Management & Filtering`, `ESAppProtocol.swift`, `App Lifecycle & Application Delegate`, `App Icon & Asset Pipeline`?**
  _High betweenness centrality (0.136) - this node is a cross-community bridge._
- **Why does `AppState` connect `.bottomActionBar` to `Authentication & Security Lock`, `MissingAppsSheet.swift`, `TouchBarType`, `Window Layout & Management`, `.panel()`, `macOS TouchBar Integration`, `SectionHeader.swift`, `Log Management & Filtering`, `macOS TouchBar Integration`, `AddAppSheet.swift`, `App Icon & Asset Pipeline`, `MainUIButtons.swift`, `ContentView.swift`?**
  _High betweenness centrality (0.110) - this node is a cross-community bridge._
- **Are the 2 inferred relationships involving `ESManager` (e.g. with `.createClient()` and `.dispatchProcessEvent()`) actually correct?**
  _`ESManager` has 2 INFERRED edges - model-reasoned connections that need verification._
- **Are the 8 inferred relationships involving `AppState` (e.g. with `.body` and `.appSection()`) actually correct?**
  _`AppState` has 8 INFERRED edges - model-reasoned connections that need verification._
- **Are the 4 inferred relationships involving `LogsSettingsTab` (e.g. with `LogDragAutoScroller` and `LogSelectionManager`) actually correct?**
  _`LogsSettingsTab` has 4 INFERRED edges - model-reasoned connections that need verification._
- **What connects `Notification.Name`, `NSTouchBarItem.Identifier`, `.isWindowVisible` to the rest of the system?**
  _239 weakly-connected nodes found - possible documentation gaps or missing edges._