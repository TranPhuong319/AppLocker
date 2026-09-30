# Graph Report - AppLocker  (2026-10-01)

## Corpus Check
- 20 files · ~276,012 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 1273 nodes · 2650 edges · 106 communities (72 shown, 34 thin omitted)
- Extraction: 92% EXTRACTED · 8% INFERRED · 0% AMBIGUOUS · INFERRED: 209 edges (avg confidence: 0.83)
- Token cost: 500 input · 200 output

## Community Hubs (Navigation)
- Batch Auth UI & Window Controller
- App Lifecycle & Auto-Update
- Touch Bar & NSToolbar
- ESExtension NOTIFY_EXEC Engine
- Window Layout & Drag Hosting
- AUTH_EXEC & File Tamper Protection
- Speckit Bash Scripts
- Agent Rules & Architecture Docs
- AppState Core & Search Filtering
- XPC Client & ES Communication
- ESManager & Safety Valve
- Settings Tab Views
- Main UI Buttons & Rows
- AppDelegate & About Window
- GitHub CI Localization Scripts
- SwiftUI Preview Mocks
- Appearance Settings Tab
- Window Controllers Hub
- Extension Installer & XPC Lifecycle
- Architecture Docs & System Overview
- Module Group 20
- Module Group 21
- Module Group 22
- Module Group 23
- Module Group 24
- Module Group 25
- Module Group 26
- Module Group 27
- Module Group 28
- Module Group 29
- Module Group 30
- Module Group 31
- Module Group 32
- Module Group 33
- Module Group 34
- Module Group 35
- Module Group 36
- Module Group 37
- Module Group 38
- Module Group 39
- Module Group 40
- Module Group 41
- Module Group 42
- Module Group 43
- Module Group 44
- Module Group 45
- Module Group 46
- Module Group 47
- Module Group 48
- Module Group 49
- Module Group 50
- Module Group 51
- Module Group 52
- Module Group 53
- Module Group 54
- Module Group 55
- Module Group 56
- Module Group 57
- Module Group 58
- Module Group 59
- Module Group 60
- Module Group 61
- Module Group 62
- Module Group 63
- Module Group 64
- Module Group 65
- Module Group 66
- Module Group 67
- Module Group 68
- Module Group 69
- Module Group 70
- Module Group 71
- Module Group 72
- Module Group 73
- Module Group 74
- Module Group 75
- Module Group 76
- Module Group 77
- Module Group 78
- Module Group 79
- Module Group 80
- Module Group 81
- Module Group 82
- Module Group 83
- Module Group 84
- Module Group 85
- Module Group 86
- Module Group 87
- Module Group 88
-  Agents Skills Speckit Converg
-  Agents Skills Speckit Tasksto
-  Github Issue Bug Report
-  Github Issue Feature
-  Github Issue Template Config 
-  Github Pr Template
-  Github Workflows Main Ci
- Applock Resources Icon Svg
- Applocker Appearance Controlle
- Applocker Appearance View Sett
- Docs Images Icon
- Docs Images Screenshots Menuba
- Security Md
- Specs 003 Checklists Requireme
- Specs 003 Fix Uninstall Spec
- Specs 005 Checklists Requireme
- Specs 005 Native Numeric Spec

## God Nodes (most connected - your core abstractions)
1. `ESManager` - 103 edges
2. `Logfile` - 99 edges
3. `AppState` - 73 edges
4. `AppDelegate` - 64 edges
5. `ESMessage` - 33 edges
6. `XPCServer` - 31 edges
7. `InstalledApp` - 31 edges
8. `AppUpdater` - 30 edges
9. `ESSafetyValve` - 24 edges
10. `LogStore` - 24 edges

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
- **AppLocker UI Architecture Stack** — _agents_rules_ui_design_liquid_glass, _agents_rules_ui_window_architecture_appkit_skeleton, _agents_rules_ui_window_architecture_observable, _agents_rules_concurrency_mainactor [INFERRED 0.90]
- **AppLocker UI Surfaces** — docs_images_screenshots_main, docs_images_screenshots_auth, docs_images_screenshots_menubar, docs_images_screenshots_batch [INFERRED 0.90]
- **GitHub Contribution Workflow** — _github_issue_bug_report, _github_issue_feature, _github_pr_template, _github_workflows_main_ci [INFERRED 0.90]
- **Security Core (Crypto + XPC + Anti-Tamper)** — _spec_existing_architecture_mutual_ecdsa, readme_anti_tampering, _agents_rules_xpc_and_security_xpc_reconnect, _agents_rules_architecture_cryptokit [INFERRED 0.90]
- **Speckit Template System** — _specify_templates_spec, _specify_templates_plan, _specify_templates_tasks, _specify_templates_checklist, _specify_templates_constitution [INFERRED 0.90]
- **Speckit Development Workflow** — _agents_skills_speckit_specify_skill, _agents_skills_speckit_plan_skill, _agents_skills_speckit_tasks_skill, _agents_skills_speckit_implement_skill, _agents_skills_speckit_analyze_skill [INFERRED 0.95]

## Communities (106 total, 34 thin omitted)

### Community 0 - "Batch Auth UI & Window Controller"
Cohesion: 0.06
Nodes (40): BatchAuthWindowController, .isWindowVisible, Bool, NSCoder, NSWindow, BatchAppRowView, .body, BatchAuthView (+32 more)

### Community 1 - "App Lifecycle & Auto-Update"
Cohesion: 0.08
Nodes (27): DispatchSourceFileSystemObject, DispatchSourceTimer, Equatable, es_process_t, OpaquePointer, Bool, Int32, Void (+19 more)

### Community 2 - "Touch Bar & NSToolbar"
Cohesion: 0.09
Nodes (24): DragHostingView, EqualWidthKey, LiquidGlassBackgroundModifier, LiquidGlassBarModifier, LiquidGlassCapsuleModifier, LiquidGlassCardModifier, LiquidGlassCircleModifier, LiquidGlassContainer (+16 more)

### Community 3 - "ESExtension NOTIFY_EXEC Engine"
Cohesion: 0.17
Nodes (14): es_auth_result_t, es_event_rename_t, es_message_t, es_string_token_t, Bool, OpaquePointer, OpaquePointer, ESMessage (+6 more)

### Community 4 - "Window Layout & Drag Hosting"
Cohesion: 0.13
Nodes (29): check-prerequisites.sh script, check_dir(), check_file(), find_specify_root(), format_speckit_command(), get_current_branch(), get_feature_paths(), get_invoke_separator() (+21 more)

### Community 5 - "AUTH_EXEC & File Tamper Protection"
Cohesion: 0.09
Nodes (14): .bottomActionBar, .bottomActionBar, NSWindow, AppState, .searchTextLockApps, .searchTextUnlockableApps, Bool, Date (+6 more)

### Community 6 - "Speckit Bash Scripts"
Cohesion: 0.08
Nodes (29): AppLocker Agent Rules, AppIconProvider NSCache, Clean Architecture & Platform API Rules, CryptoKit ECDSA Auth, YAGNI (You Aren't Gonna Need It), @MainActor UI Isolation, Swift Concurrency Rules, Apple Unified Logging (os.Logger) (+21 more)

### Community 7 - "Agent Rules & Architecture Docs"
Cohesion: 0.11
Nodes (16): SettingsTab, appearance, .displayName, general, .iconName, .id, logs, security (+8 more)

### Community 8 - "AppState Core & Search Filtering"
Cohesion: 0.11
Nodes (19): AddAppRow, DeleteQueueRow, LockedAppRow, .body, MissingAppRow, .body, Bool, Void (+11 more)

### Community 9 - "XPC Client & ES Communication"
Cohesion: 0.15
Nodes (8): DispatchQueue, es_event_type_t, ESAuthorizer, ESClientObject, ESTamper, Bool, OpaquePointer, Sendable

### Community 10 - "ESManager & Safety Valve"
Cohesion: 0.16
Nodes (8): Combine, Darwin, EndpointSecurity, Foundation, os, OSLog, Security, SystemConfiguration

### Community 11 - "Settings Tab Views"
Cohesion: 0.10
Nodes (9): AppDelegate, Bool, Notification.Name, NSApplicationDelegate, NSMenuDelegate, NSStatusItem, UNNotificationRequest, UNUserNotificationCenterDelegate (+1 more)

### Community 12 - "Main UI Buttons & Rows"
Cohesion: 0.14
Nodes (19): argparse, collections, get_lang_name(), main(), write_stats(), generate_html(), generate_markdown(), get_commits() (+11 more)

### Community 13 - "AppDelegate & About Window"
Cohesion: 0.14
Nodes (10): MockLockManager, Bool, Int, Set, S, Sequence, fuzzyMatch(), String (+2 more)

### Community 14 - "GitHub CI Localization Scripts"
Cohesion: 0.16
Nodes (9): AnyObject, NSButton, Notification, NSTouchBarItem, NSWindow, TouchBarManager, NSTouchBar, NSTouchBarDelegate (+1 more)

### Community 15 - "SwiftUI Preview Mocks"
Cohesion: 0.21
Nodes (12): AppearanceSettingsTab, .body, Bool, ThemeThumbnailView, .body, .bottomWindowLayer, .darkWallpaper, .lightWallpaper (+4 more)

### Community 16 - "Appearance Settings Tab"
Cohesion: 0.11
Nodes (20): LogSubsystemFilter, all, .displayName, esExtension, .id, mainApp, .subsystemPrefix, LogTimeRange (+12 more)

### Community 17 - "Window Controllers Hub"
Cohesion: 0.16
Nodes (10): NSApplication, .appDelegate, NSAlert, AlertResult, button, cancelled, AlertShow, Bool (+2 more)

### Community 18 - "Extension Installer & XPC Lifecycle"
Cohesion: 0.18
Nodes (11): Action, install, uninstall, ExtensionInstaller, Bool, Error, Void, OSSystemExtensionProperties (+3 more)

### Community 19 - "Architecture Docs & System Overview"
Cohesion: 0.14
Nodes (14): LogsSettingsTab, .emptyPlaceholder, .exportFilename, .loadingPlaceholder, .logListContent, LogTextDocument, Bool, DateFormatter (+6 more)

### Community 20 - "Module Group 20"
Cohesion: 0.20
Nodes (11): .body, LogStore, .searchText, .selectedLevel, .selectedSubsystem, .selectedTimeRange, Bool, Void (+3 more)

### Community 21 - "Module Group 21"
Cohesion: 0.14
Nodes (17): ESExtension Endpoint Security Daemon, Process Interception Flow (SIGSTOP/SIGCONT), AppLocker Main Application, Mutual ECDSA P-256 XPC Handshake, Shared Core Framework, AppLocker Demo Animation, Touch ID Auth Dialog Screenshot, Batch Auth Multi-App Screenshot (+9 more)

### Community 22 - "Module Group 22"
Cohesion: 0.12
Nodes (16): LocalizedStringKey, ThemeMode, dark, .displayName, .id, light, system, LocalizedStringKey (+8 more)

### Community 23 - "Module Group 23"
Cohesion: 0.20
Nodes (7): audit_token_t, pid_t, audit_token_t, Bool, Int, Int32, pid_t

### Community 24 - "Module Group 24"
Cohesion: 0.15
Nodes (8): GeneralSettingsTab, .body, Bool, Bool, UpdatesSettingsTab, .body, .currentVersionRow, .selectedChannel

### Community 25 - "Module Group 25"
Cohesion: 0.21
Nodes (8): ConfigLoadResult, ConfigStore, .configURL, .userDirectoryURL, Bool, Int, URL, Void

### Community 26 - "Module Group 26"
Cohesion: 0.15
Nodes (10): ContentView, .contentView, .deleteQueueNotificationBar, .emptyStateView, .mainListView, .missingAppsWarningButton, .scrollEdgeDissolveMask, LocalizedStringKey (+2 more)

### Community 27 - "Module Group 27"
Cohesion: 0.21
Nodes (8): SecuritySettingsTab, .body, .lockedStateView, .unlockedContent, Bool, Int, Binding, Double

### Community 28 - "Module Group 28"
Cohesion: 0.24
Nodes (4): LockES, Bool, Int, cdHash()

### Community 29 - "Module Group 29"
Cohesion: 0.16
Nodes (4): AppKit, SMAppService.Status, .description, ServiceManagement

### Community 30 - "Module Group 30"
Cohesion: 0.18
Nodes (10): NSCoder, Bool, NSSize, NSViewController, NSWindow, WindowConfiguration, WindowManager, AboutView (+2 more)

### Community 31 - "Module Group 31"
Cohesion: 0.24
Nodes (6): .body, AppIconProvider, CGFloat, NSImage, Bool, Date

### Community 32 - "Module Group 32"
Cohesion: 0.19
Nodes (9): Coordinator, .logList, ScrollBottomTracker, Context, Sendable, Void, NSObject, NSObjectProtocol (+1 more)

### Community 33 - "Module Group 33"
Cohesion: 0.26
Nodes (8): Codable, Decoder, LockedAppConfig, Bool, Int, uid_t, URL, UserConfig

### Community 34 - "Module Group 34"
Cohesion: 0.17
Nodes (4): Observation, SwiftUI, SystemExtensions, UniformTypeIdentifiers

### Community 35 - "Module Group 35"
Cohesion: 0.15
Nodes (6): Bool, escaping, LAContext, LocalAuthentication, MainActor, AuthenticationManager

### Community 36 - "Module Group 36"
Cohesion: 0.15
Nodes (10): .body, .body, AppIconView, Bool, CGFloat, NSImage, AppRowButtonStyle, View (+2 more)

### Community 37 - "Module Group 37"
Cohesion: 0.18
Nodes (9): SectionHeader, .body, LocalizedStringKey, AddAppSheet, .body, .lockButtonTitle, Bool, CGFloat (+1 more)

### Community 38 - "Module Group 38"
Cohesion: 0.19
Nodes (8): AppUpdater, .automaticallyChecksForUpdates, .automaticallyDownloadsUpdates, .currentChannel, .downloadState, .hasAvailableUpdate, SPUStandardUpdaterController, Timer

### Community 39 - "Module Group 39"
Cohesion: 0.27
Nodes (9): es_event_exec_t, es_file_t, OpaquePointer, execArguments(), processPath(), safePath(), string(), pid_t (+1 more)

### Community 40 - "Module Group 40"
Cohesion: 0.21
Nodes (4): AnyObject, AppUpdaterBridgeDelegate, SPUUpdater, SUAppcastItem

### Community 41 - "Module Group 41"
Cohesion: 0.30
Nodes (5): MissingAppsTouchBarItem, NSCoder, NSTouchBarItem, NSButtonTouchBarItem, NSRect

### Community 42 - "Module Group 42"
Cohesion: 0.29
Nodes (8): AppLogEntry, .levelFilter, .subsystemShort, Date, DateFormatter, OSLogEntryLog, String, UUID

### Community 43 - "Module Group 43"
Cohesion: 0.21
Nodes (5): Bool, AgentAction, check, install, uninstall

### Community 44 - "Module Group 44"
Cohesion: 0.20
Nodes (5): HotKeyManager, Carbon, Cocoa, EventHandlerRef, EventHotKeyRef

### Community 45 - "Module Group 45"
Cohesion: 0.20
Nodes (6): AboutWindowController, SettingsWindowController, Notification, WelcomeWindowController, NSWindowController, NSWindowDelegate

### Community 46 - "Module Group 46"
Cohesion: 0.22
Nodes (6): AppListWindowController, Notification, NSCoder, NSViewController, NSWindow, NSHostingController

### Community 47 - "Module Group 47"
Cohesion: 0.18
Nodes (5): MissingAppsSheet, .bottomActionBar, .missingPaths, .topHeader, CGFloat

### Community 48 - "Module Group 48"
Cohesion: 0.18
Nodes (10): LogEntryRow, .body, .categoryBadge, .copyIcon, .levelColor, .levelDot, .subsystemBadge, Bool (+2 more)

### Community 49 - "Module Group 49"
Cohesion: 0.22
Nodes (3): LockManagerProtocol, Bool, Int

### Community 50 - "Module Group 50"
Cohesion: 0.18
Nodes (11): LogLevelFilter, all, debug, .displayName, error, fault, .id, info (+3 more)

### Community 51 - "Module Group 51"
Cohesion: 0.22
Nodes (10): Channel, beta, stable, UpdateDownloadState, downloaded, notDownloaded, UpdateNotificationAction, UpdaterDelegate (+2 more)

### Community 52 - "Module Group 52"
Cohesion: 0.25
Nodes (4): LoadedConfigs, Bool, Set, uid_t

### Community 53 - "Module Group 53"
Cohesion: 0.24
Nodes (8): Bool, NSXPCConnection, NSXPCListener, SecRequirement, CodeSignatureValidator, audit_token_t, Bool, NSXPCConnection

### Community 54 - "Module Group 54"
Cohesion: 0.22
Nodes (6): DeleteQueueTouchBarButton, .intrinsicContentSize, LockTouchBarButton, NSTouchBarItem.Identifier, NSSize, NSButton

### Community 55 - "Module Group 55"
Cohesion: 0.29
Nodes (5): SearchTouchBarItem, Any, Notification, NSPopoverTouchBarItem, NSSearchFieldDelegate

### Community 57 - "Module Group 57"
Cohesion: 0.22
Nodes (8): audit_token_t, NSXPCConnection, audit_token_t, NSXPCConnection, libbsm, libproc, notify, proc_info

### Community 58 - "Module Group 58"
Cohesion: 0.33
Nodes (4): ESAppProtocol, Bool, Int32, Void

### Community 59 - "Module Group 59"
Cohesion: 0.22
Nodes (6): .body, DeleteQueueSheet, .topHeader, CGFloat, LockingPopupSheet, .body

### Community 60 - "Module Group 60"
Cohesion: 0.31
Nodes (3): Bool, Void, TimeInterval

### Community 61 - "Module Group 61"
Cohesion: 0.28
Nodes (9): BetaGitHubAsset, BetaGitHubRelease, CodingKeys, assets, browserDownloadUrl, isPrerelease, name, CodingKey (+1 more)

### Community 62 - "Module Group 62"
Cohesion: 0.25
Nodes (8): Speckit Implement Skill, Speckit Plan Skill, Speckit Specify Skill, Speckit Tasks Skill, Plan Template, Spec Template, Tasks Template, Speckit Workflow Configuration

### Community 63 - "Module Group 63"
Cohesion: 0.32
Nodes (6): NSView, .enclosingSplitView, SidebarCollapsePreventer, Context, NSSplitView, NSViewRepresentable

### Community 64 - "Module Group 64"
Cohesion: 0.25
Nodes (5): Void, UNNotification, UNNotificationPresentationOptions, UNNotificationResponse, UNUserNotificationCenter

### Community 65 - "Module Group 65"
Cohesion: 0.43
Nodes (3): Data, Bool, uid_t

### Community 66 - "Module Group 66"
Cohesion: 0.25
Nodes (8): Bundle, .appBuild, .appIcon, .appName, .appVersion, .copyright, .fullVersion, NSImage

### Community 67 - "Module Group 67"
Cohesion: 0.25
Nodes (8): CodingKeys, bundleID, cdhash, execFile, isHidden, name, path, sha256

### Community 69 - "Module Group 69"
Cohesion: 0.29
Nodes (7): AgentManageResult, alreadyInstalled, alreadyUninstalled, failed, installed, uninstalled, Error

### Community 70 - "Module Group 70"
Cohesion: 0.40
Nodes (4): Bool, WelcomeView, .body, .licenseText

### Community 74 - "Module Group 74"
Cohesion: 0.40
Nodes (5): TouchBarType, addAppPopup, deleteQueuePopup, mainWindow, missingAppsPopup

### Community 78 - "Module Group 78"
Cohesion: 0.50
Nodes (3): Any, Bool, URL

### Community 79 - "Module Group 79"
Cohesion: 0.67
Nodes (3): AUTH_EXEC PID Assignment, NOTIFY_EXEC Pre/Post Exec Timing, POSIX Liveness & PID Recycling Defense

## Knowledge Gaps
- **191 isolated node(s):** `UpdateNotificationAction`, `Notification.Name`, `NSTouchBarItem.Identifier`, `.authButtonTitle`, `.bottomActionBar` (+186 more)
  These have ≤1 connection - possible missing edges or undocumented components. (Counts symbols only; 389 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **34 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `String` connect `AppDelegate & About Window` to `Batch Auth UI & Window Controller`, `App Lifecycle & Auto-Update`, `ESExtension NOTIFY_EXEC Engine`, `AUTH_EXEC & File Tamper Protection`, `AppState Core & Search Filtering`, `XPC Client & ES Communication`, `Settings Tab Views`, `GitHub CI Localization Scripts`, `SwiftUI Preview Mocks`, `Window Controllers Hub`, `Module Group 22`, `Module Group 23`, `Module Group 24`, `Module Group 25`, `Module Group 26`, `Module Group 28`, `Module Group 29`, `Module Group 30`, `Module Group 31`, `Module Group 33`, `Module Group 35`, `Module Group 36`, `Module Group 37`, `Module Group 38`, `Module Group 39`, `Module Group 40`, `Module Group 43`, `Module Group 47`, `Module Group 49`, `Module Group 51`, `Module Group 52`, `Module Group 58`, `Module Group 59`, `Module Group 61`, `Module Group 64`, `Module Group 65`, `Module Group 66`, `Module Group 67`, `Module Group 70`, `Module Group 71`, `Module Group 75`, `Module Group 76`?**
  _High betweenness centrality (0.277) - this node is a cross-community bridge._
- **Why does `ESManager` connect `App Lifecycle & Auto-Update` to `Module Group 32`, `Module Group 65`, `ESExtension NOTIFY_EXEC Engine`, `Module Group 39`, `XPC Client & ES Communication`, `ESManager & Safety Valve`, `AppDelegate & About Window`, `Module Group 52`, `Module Group 53`, `Module Group 23`, `Module Group 58`?**
  _High betweenness centrality (0.140) - this node is a cross-community bridge._
- **Why does `Logfile` connect `Batch Auth UI & Window Controller` to `App Lifecycle & Auto-Update`, `ESExtension NOTIFY_EXEC Engine`, `XPC Client & ES Communication`, `ESManager & Safety Valve`, `Settings Tab Views`, `Window Controllers Hub`, `Extension Installer & XPC Lifecycle`, `Module Group 23`, `Module Group 25`, `Module Group 27`, `Module Group 28`, `Module Group 35`, `Module Group 39`, `Module Group 43`, `Module Group 44`, `Module Group 52`, `Module Group 53`, `Module Group 60`, `Module Group 65`, `Module Group 68`, `Module Group 75`, `Module Group 77`?**
  _High betweenness centrality (0.099) - this node is a cross-community bridge._
- **Are the 7 inferred relationships involving `AppState` (e.g. with `.body` and `.appSection()`) actually correct?**
  _`AppState` has 7 INFERRED edges - model-reasoned connections that need verification._
- **What connects `UpdateNotificationAction`, `Notification.Name`, `NSTouchBarItem.Identifier` to the rest of the system?**
  _191 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Batch Auth UI & Window Controller` be split into smaller, more focused modules?**
  _Cohesion score 0.05647517039922103 - nodes in this community are weakly interconnected._
- **Should `App Lifecycle & Auto-Update` be split into smaller, more focused modules?**
  _Cohesion score 0.07536231884057971 - nodes in this community are weakly interconnected._