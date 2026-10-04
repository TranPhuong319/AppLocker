# Graph Report - AppLocker  (2026-10-04)

## Corpus Check
- 5 files · ~279,893 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 1542 nodes · 2688 edges · 164 communities (53 shown, 111 thin omitted)
- Extraction: 94% EXTRACTED · 6% INFERRED · 0% AMBIGUOUS · INFERRED: 166 edges (avg confidence: 0.83)
- Token cost: 0 input · 0 output

## Community Hubs (Navigation)
- TouchBarBuilders.swift / AnyObject / NSButton
- BatchAuthView.swift / BatchAppRowView / .body
- ConfigLoadResult / ConfigStore / .configURL
- DispatchQueue / es_auth_result_t / es_event_rename_t
- .actionsSection / .userNotificationCenter() / Void
- SettingsWindowController / .constrained() / .extraFrameInsets()
- AnyObject / .preview() / MockLockManager
- ESXPCClient / .connect() / .createConnection()
- check-prerequisites.sh / check-prerequisites.sh script / common.sh
- .show() / .bottomActionBar / AppState
- LogsSettingsTab+AutoScroll.swift / LogDragAutoScroller / .direction
- .openAppList() / .openSettings() / .openSystemSettingsForExtension()
- AppLocker Agent Rules / AppIconProvider NSCache / Clean Architecture & Platform API Rules
- ESXPCClient.swift / CallServiceObserver.swift / Combine
- LogSelectionManager.swift / LogSelectionManager / .copySelected()
- AppKit / SettingsWindowController.swift / Notification.Name
- AnyShapeStyle / LogsSettingsTab / .bottomBar()
- audit_token_t / DispatchSourceFileSystemObject / DispatchSourceTimer
- argparse / collections / check_localization.py
- MainUIButtons.swift / AddAppRow / .body
- .body / LogReader / .query()
- Equatable / .handleNotifyExit() / OpaquePointer
- WindowLayout.swift / EqualWidthKey / .reduce()
- AppDelegate.swift / .manageAgent() / .registerAgentWithoutImmediateLaunch()
- .init() / NSCoder / WindowManager.swift
- ContentView.swift / ContentView / .appSection()
- ESExtension Endpoint Security Daemon / Process Interception Flow (SIGSTOP/SIGCONT) / AppLocker Main Application
- AboutWindowController.swift / AboutWindowController / .show()
- .init() / NSCoder / AboutView.swift
- es_event_exec_t / es_file_t / es_string_token_t
- Bool / ThemeThumbnailView / .body
- .handleAuthSignal() / OpaquePointer / .auditToken()
- AppearanceSettingsTab.swift / AppearanceSettingsTab / .body
- SecuritySettingsTab.swift / SecuritySettingsTab / .body
- NSApplication / .appDelegate / NSAlert
- .displayEntries / AppLogEntry / .init()
- Coordinator / .attach() / .deinit()
- .architectureButton / AboutView+SystemInfo.swift / Bool
- SectionHeader.swift / SectionHeader / .body
- LogEntryRow.swift / LogEntryRow / .body
- .copyEntry() / .formatted() / .exportText()
- DragHostingView / .mouseDown() / LiquidGlassContainer
- AppIconProvider.swift / AppIconProvider / .cachedIcon()
- AppDelegate+MenuBar.swift / .addHeaderMenuItems() / .addMaintenanceMenuItems()
- .extractHashesAndPaths() / .loadInitialConfigSync() / .monitorDirectory()
- AppListWindowController.swift / AppListWindowController / .createHostingController()
- LogsSettingsTab / .init() / .logListContent
- UpdatesSettingsTab.swift / Bool / String
- .performReset() / .resetApp() / .checkAndMoveToApplications()
- LogLevelFilter / all / debug
- LogTimeRange / all / currentSession
- .listener() / Bool / NSXPCConnection
- AppDelegate+Actions.swift / AppDelegate+Agent.swift / AgentManageResult
- AppLocker/Bridging-Header.h / audit_token_t / NSXPCConnection
- HotKeyManager.swift / HotKeyManager / .deinit()
- ESAppProtocol.swift / ESAppProtocol / .allowConfigAccess()
- .bottomActionBar / .addOtherApps() / .processSelectedPaths()
- Speckit Implement Skill / Speckit Plan Skill / Speckit Specify Skill
- AddAppSheet.swift / AddAppSheet / .body
- SettingsTab.swift / LocalizedStringKey / UpdateChannel
- CallServiceObserver / .handleNotificationFired() / .init()
- LogSubsystemFilter / all / .displayName
- Data / .isAllowedIncomingCall() / .isPathInLockedBundle()
- .enable() / .init() / ESTamper
- LiquidGlassBackgroundModifier / .body() / .liquidGlassBackground()
- AppRowButtonStyle.swift / AppRowButtonStyle / .makeBody()
- LogsSettingsTab+ContextMenu.swift / LogRowBoundsPreference / .reduce()
- pid_t / String / TTYNotifier
- S / Sequence / FuzzySearch.swift
- .createAppMenuItem() / .createEditMenuItem() / .createWindowMenuItem()
- TouchBarType / addAppPopup / deleteQueuePopup
- ESXPCProtocol.swift / ESXPCProtocol / .notifyBlockedExec()
- CustomApplication.swift / CustomApplication / .sendEvent()
- .panel() / Any / Bool
- .bringFrontmostWindow() / .checkForUpdates() / String
- Speckit Checklist Skill / Checklist Template
- License (English) / License (Vietnamese)
- AppLocker AppIcon Assets / AppLocker Social Preview
- AppLocker Usage Guide (EN) / AppLocker Usage Guide (VI)
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
- Color
- AppIcon icon_32x32.png
- AppIcon icon_512x512.png
- LockedAppConfig
- LockedAppConfig
- Bool
- CGPoint
- CGRect
- DateFormatter
- Int
- UnsafePointer
- Int
- uid_t
- UUID
- Community 158
- Community 159
- Community 160

## God Nodes (most connected - your core abstractions)
1. `ESManager` - 106 edges
2. `AppState` - 74 edges
3. `AppDelegate` - 44 edges
4. `XPCServer` - 32 edges
5. `AppUpdater` - 31 edges
6. `LogStore` - 26 edges
7. `LogSelectionManager` - 24 edges
8. `SettingsTab` - 24 edges
9. `ESSafetyValve` - 23 edges
10. `TouchBarManager` - 22 edges

## Surprising Connections (you probably didn't know these)
- `AppLocker Demo Animation` --conceptually_related_to--> `AppLocker Project Overview`  [INFERRED]
  docs/gif/demo.gif → README.md
- `AppState @Observable Migration` --semantically_similar_to--> `@Observable State Management`  [INFERRED] [semantically similar]
  specs/001-migrate-observable-state/spec.md → .agents/rules/ui-window-architecture.md
- `Kernel-Level Process Interception` --semantically_similar_to--> `Process Interception Flow (SIGSTOP/SIGCONT)`  [INFERRED] [semantically similar]
  README.md → .spec/existing-architecture.md
- `Main Dashboard Screenshot` --conceptually_related_to--> `AppLocker Main Application`  [INFERRED]
  docs/images/screenshots/screenshot-main.png → .spec/existing-architecture.md
- `Touch ID Auth Dialog Screenshot` --conceptually_related_to--> `Batch Authentication Flow`  [INFERRED]
  docs/images/screenshots/screenshot-auth.png → README.md

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

## Communities (164 total, 111 thin omitted)

### Community 0 - "TouchBarBuilders.swift / AnyObject / NSButton"
Cohesion: 0.06
Nodes (10): DeleteQueueTouchBarButton, .intrinsicContentSize, LockTouchBarButton, MissingAppsTouchBarItem, NSTouchBarItem.Identifier, SearchTouchBarItem, TouchBarManager, NSView (+2 more)

### Community 1 - "BatchAuthView.swift / BatchAppRowView / .body"
Cohesion: 0.06
Nodes (15): ConfigLoadResult, ConfigStore, .configURL, .userDirectoryURL, LockES, CodingKeys, bundleID, cdhash (+7 more)

### Community 2 - "ConfigLoadResult / ConfigStore / .configURL"
Cohesion: 0.09
Nodes (3): ESSafetyValve, ESClientObject, ESTamper

### Community 3 - "DispatchQueue / es_auth_result_t / es_event_rename_t"
Cohesion: 0.06
Nodes (16): BatchAppRowView, .body, .checkmarkIndicator, BatchAuthView, .authButtonTitle, .body, .bottomActionBar, .headerTitle (+8 more)

### Community 4 - ".actionsSection / .userNotificationCenter() / Void"
Cohesion: 0.06
Nodes (19): .actionsSection, AppUpdater, .automaticallyChecksForUpdates, .automaticallyDownloadsUpdates, .currentChannel, .downloadState, .hasAvailableUpdate, BetaGitHubAsset (+11 more)

### Community 5 - "SettingsWindowController / .constrained() / .extraFrameInsets()"
Cohesion: 0.06
Nodes (20): SettingsWindowController, GeneralSettingsTab, .body, SettingsTab, appearance, .displayName, general, .iconName (+12 more)

### Community 6 - "AnyObject / .preview() / MockLockManager"
Cohesion: 0.05
Nodes (14): MockLockManager, LockManagerProtocol, AppSource, system, user, Bundle, .appBuild, .appIcon (+6 more)

### Community 7 - "ESXPCClient / .connect() / .createConnection()"
Cohesion: 0.09
Nodes (6): ESXPCClient, Action, install, uninstall, ExtensionInstaller, .isInstalled

### Community 8 - "check-prerequisites.sh / check-prerequisites.sh script / common.sh"
Cohesion: 0.09
Nodes (6): .bottomActionBar, AppState, .searchTextLockApps, .searchTextUnlockableApps, .systemUnlockableApps, .userUnlockableApps

### Community 9 - ".show() / .bottomActionBar / AppState"
Cohesion: 0.13
Nodes (29): check-prerequisites.sh script, check_dir(), check_file(), find_specify_root(), format_speckit_command(), get_current_branch(), get_feature_paths(), get_invoke_separator() (+21 more)

### Community 10 - "LogsSettingsTab+AutoScroll.swift / LogDragAutoScroller / .direction"
Cohesion: 0.09
Nodes (9): LogDragAutoScroller, .direction, .dragCurrentInContent, .dragStartInContent, .visibleContentBottom, .visibleContentTop, LogSearchFocusModifier, LogsSettingsTab (+1 more)

### Community 11 - ".openAppList() / .openSettings() / .openSystemSettingsForExtension()"
Cohesion: 0.07
Nodes (30): AppLocker Agent Rules, AppIconProvider NSCache, Clean Architecture & Platform API Rules, CryptoKit ECDSA Auth, @MainActor UI Isolation, Swift Concurrency Rules, Apple Unified Logging (os.Logger), SwiftLint Zero Warnings Policy (+22 more)

### Community 12 - "AppLocker Agent Rules / AppIconProvider NSCache / Clean Architecture & Platform API Rules"
Cohesion: 0.11
Nodes (3): LogSelectionManager, .hasSelection, .selectedCount

### Community 13 - "ESXPCClient.swift / CallServiceObserver.swift / Combine"
Cohesion: 0.15
Nodes (7): Combine, Darwin, EndpointSecurity, Foundation, os, Security, SystemConfiguration

### Community 14 - "LogSelectionManager.swift / LogSelectionManager / .copySelected()"
Cohesion: 0.09
Nodes (5): .isAgentActive, .isLaunchedByLaunchd, AppDelegate, Notification.Name, UserNotifications

### Community 15 - "AppKit / SettingsWindowController.swift / Notification.Name"
Cohesion: 0.11
Nodes (4): BlockedNotification, .baseConfigDirectory, .currentLanguage, ESManager

### Community 16 - "AnyShapeStyle / LogsSettingsTab / .bottomBar()"
Cohesion: 0.10
Nodes (13): LogsSettingsTab, .clearIcon, .copyStatusIcon, .dragSelectionOverlay, .emptyPlaceholder, .exportFilename, .exportIcon, .groupRepeatingIcon (+5 more)

### Community 17 - "audit_token_t / DispatchSourceFileSystemObject / DispatchSourceTimer"
Cohesion: 0.13
Nodes (4): AppDelegate, MenuBarImageView, Notification.Name, Symbols

### Community 18 - "argparse / collections / check_localization.py"
Cohesion: 0.14
Nodes (12): get_lang_name(), main(), write_stats(), generate_html(), generate_markdown(), get_commits(), get_current_branch(), get_last_stable_tag() (+4 more)

### Community 19 - "MainUIButtons.swift / AddAppRow / .body"
Cohesion: 0.16
Nodes (12): AddAppRow, .body, .selectionIndicator, DeleteQueueRow, .body, LockedAppRow, .body, MissingAppRow (+4 more)

### Community 20 - ".body / LogReader / .query()"
Cohesion: 0.17
Nodes (7): .body, LogReader, LogStore, .searchText, .selectedLevel, .selectedSubsystem, .selectedTimeRange

### Community 21 - "Equatable / .handleNotifyExit() / OpaquePointer"
Cohesion: 0.17
Nodes (7): EqualWidthKey, LiquidGlassBarModifier, LiquidGlassCapsuleModifier, LiquidGlassCardModifier, LiquidGlassCircleModifier, View, WindowLayout

### Community 23 - "AppDelegate.swift / .manageAgent() / .registerAgentWithoutImmediateLaunch()"
Cohesion: 0.12
Nodes (9): ContentView, .body, .contentView, .deleteQueueNotificationBar, .emptyStateView, .mainListView, .missingAppsWarningButton, .scrollEdgeDissolveMask (+1 more)

### Community 25 - "ContentView.swift / ContentView / .appSection()"
Cohesion: 0.20
Nodes (4): execArguments(), processPath(), safePath(), string()

### Community 26 - "ESExtension Endpoint Security Daemon / Process Interception Flow (SIGSTOP/SIGCONT) / AppLocker Main Application"
Cohesion: 0.14
Nodes (17): ESExtension Endpoint Security Daemon, Process Interception Flow (SIGSTOP/SIGCONT), AppLocker Main Application, Mutual ECDSA P-256 XPC Handshake, Shared Core Framework, AppLocker Demo Animation, Touch ID Auth Dialog Screenshot, Batch Auth Multi-App Screenshot (+9 more)

### Community 27 - "AboutWindowController.swift / AboutWindowController / .show()"
Cohesion: 0.13
Nodes (4): AboutWindowController, BatchAuthWindowController, .isWindowVisible, WelcomeWindowController

### Community 28 - ".init() / NSCoder / AboutView.swift"
Cohesion: 0.12
Nodes (7): AboutView, .appIdentitySection, .copyVersionIcon, .footerSection, .isExtensionActive, .taglineSection, .versionPill

### Community 29 - "es_event_exec_t / es_file_t / es_string_token_t"
Cohesion: 0.17
Nodes (5): Observation, OSLog, SwiftUI, SystemExtensions, UniformTypeIdentifiers

### Community 30 - "Bool / ThemeThumbnailView / .body"
Cohesion: 0.19
Nodes (4): SecuritySettingsTab, .body, .lockedStateView, .unlockedContent

### Community 31 - ".handleAuthSignal() / OpaquePointer / .auditToken()"
Cohesion: 0.17
Nodes (8): AppearanceSettingsTab, .body, ThemeMode, dark, .displayName, .id, light, system

### Community 32 - "AppearanceSettingsTab.swift / AppearanceSettingsTab / .body"
Cohesion: 0.23
Nodes (8): ThemeThumbnailView, .body, .bottomWindowLayer, .darkWallpaper, .lightWallpaper, .menuBarLayer, .topPillLayer, .wallpaperLayer

### Community 33 - "SecuritySettingsTab.swift / SecuritySettingsTab / .body"
Cohesion: 0.20
Nodes (6): NSApplication, .appDelegate, AlertResult, button, cancelled, AlertShow

### Community 34 - "NSApplication / .appDelegate / NSAlert"
Cohesion: 0.21
Nodes (6): .displayEntries, AppLogEntry, .levelFilter, .subsystemShort, GroupedLogEntry, .id

### Community 36 - "Coordinator / .attach() / .deinit()"
Cohesion: 0.22
Nodes (5): HotKeyAction, appList, resumeProtection, HotKeyManager, Carbon

### Community 38 - ".architectureButton / AboutView+SystemInfo.swift / Bool"
Cohesion: 0.18
Nodes (8): .architectureButton, SystemEnvironment, .architectureDetail, .cpuBrand, .isRunningUnderRosetta, .osVersion, SystemInfoPopoverView, .body

### Community 39 - "SectionHeader.swift / SectionHeader / .body"
Cohesion: 0.17
Nodes (6): SectionHeader, .body, DeleteQueueSheet, .body, .bottomActionBar, .topHeader

### Community 40 - "LogEntryRow.swift / LogEntryRow / .body"
Cohesion: 0.15
Nodes (8): LogEntryRow, .body, .categoryBadge, .copyIcon, .levelColor, .levelDot, .repeatBadge, .subsystemBadge

### Community 43 - "AppIconProvider.swift / AppIconProvider / .cachedIcon()"
Cohesion: 0.24
Nodes (4): DragHostingView, LiquidGlassContainer, .body, WindowDragArea

### Community 46 - "AppListWindowController.swift / AppListWindowController / .createHostingController()"
Cohesion: 0.20
Nodes (3): AppKit, Notification.Name, ServiceManagement

### Community 48 - "UpdatesSettingsTab.swift / Bool / String"
Cohesion: 0.18
Nodes (4): MissingAppsSheet, .bottomActionBar, .missingPaths, .topHeader

### Community 50 - "LogLevelFilter / all / debug"
Cohesion: 0.22
Nodes (4): UpdatesSettingsTab, .body, .currentVersionRow, .selectedChannel

### Community 51 - "LogTimeRange / all / currentSession"
Cohesion: 0.18
Nodes (10): LogLevelFilter, all, debug, .displayName, error, fault, .id, info (+2 more)

### Community 52 - ".listener() / Bool / NSXPCConnection"
Cohesion: 0.18
Nodes (10): LogTimeRange, all, currentSession, .displayName, .id, last24Hours, last6Hours, last7Days (+2 more)

### Community 55 - "AppLocker/Bridging-Header.h / audit_token_t / NSXPCConnection"
Cohesion: 0.24
Nodes (4): AboutArchitectureBadgesView, .architectureName, .body, .body

### Community 56 - "HotKeyManager.swift / HotKeyManager / .deinit()"
Cohesion: 0.20
Nodes (6): AgentManageResult, alreadyInstalled, alreadyUninstalled, failed, installed, uninstalled

### Community 59 - "Speckit Implement Skill / Speckit Plan Skill / Speckit Specify Skill"
Cohesion: 0.22
Nodes (6): AgentAction, check, install, uninstall, SMAppService.Status, .description

### Community 61 - "SettingsTab.swift / LocalizedStringKey / UpdateChannel"
Cohesion: 0.25
Nodes (8): Speckit Implement Skill, Speckit Plan Skill, Speckit Specify Skill, Speckit Tasks Skill, Plan Template, Spec Template, Tasks Template, Speckit Workflow Configuration

### Community 62 - "CallServiceObserver / .handleNotificationFired() / .init()"
Cohesion: 0.29
Nodes (3): AddAppSheet, .body, .lockButtonTitle

### Community 63 - "LogSubsystemFilter / all / .displayName"
Cohesion: 0.25
Nodes (6): UpdateChannel, beta, .description, .displayName, .id, stable

### Community 65 - ".enable() / .init() / ESTamper"
Cohesion: 0.25
Nodes (7): LogSubsystemFilter, all, .displayName, esExtension, .id, mainApp, .subsystemPrefix

### Community 72 - "S / Sequence / FuzzySearch.swift"
Cohesion: 0.40
Nodes (3): WelcomeView, .body, .licenseText

### Community 76 - "ESXPCProtocol.swift / ESXPCProtocol / .notifyBlockedExec()"
Cohesion: 0.40
Nodes (5): TouchBarType, addAppPopup, deleteQueuePopup, mainWindow, missingAppsPopup

### Community 80 - ".bringFrontmostWindow() / .checkForUpdates() / String"
Cohesion: 0.67
Nodes (3): AUTH_EXEC PID Assignment, NOTIFY_EXEC Pre/Post Exec Timing, POSIX Liveness & PID Recycling Defense

## Knowledge Gaps
- **242 isolated node(s):** `NSTouchBarItem.Identifier`, `Notification.Name`, `Notification.Name`, `UpdateNotificationAction`, `.intrinsicContentSize` (+237 more)
  These have ≤1 connection - possible missing edges or undocumented components. (Counts symbols only; 584 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **111 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `Foundation` connect `ESXPCClient.swift / CallServiceObserver.swift / Combine` to `BatchAuthView.swift / BatchAppRowView / .body`, `ConfigLoadResult / ConfigStore / .configURL`, `DispatchQueue / es_auth_result_t / es_event_rename_t`, `.actionsSection / .userNotificationCenter() / Void`, `AnyObject / .preview() / MockLockManager`, `ESXPCClient / .connect() / .createConnection()`, `AppLocker Agent Rules / AppIconProvider NSCache / Clean Architecture & Platform API Rules`, `Equatable / .handleNotifyExit() / OpaquePointer`, `WindowLayout.swift / EqualWidthKey / .reduce()`, `ContentView.swift / ContentView / .appSection()`, `AboutWindowController.swift / AboutWindowController / .show()`, `es_event_exec_t / es_file_t / es_string_token_t`, `AppDelegate+MenuBar.swift / .addHeaderMenuItems() / .addMaintenanceMenuItems()`, `AppListWindowController.swift / AppListWindowController / .createHostingController()`, `.bottomActionBar / .addOtherApps() / .processSelectedPaths()`, `Speckit Implement Skill / Speckit Plan Skill / Speckit Specify Skill`, `AddAppSheet.swift / AddAppSheet / .body`, `TouchBarType / addAppPopup / deleteQueuePopup`, `CustomApplication.swift / CustomApplication / .sendEvent()`?**
  _High betweenness centrality (0.155) - this node is a cross-community bridge._
- **Why does `ESManager` connect `AppKit / SettingsWindowController.swift / Notification.Name` to `ConfigLoadResult / ConfigStore / .configURL`, `AppIconView.swift / AppIconView / .body`, `es_process_t / .processPendingApps() / .updateIncomingCallRingingState()`, `DragHostingView / .mouseDown() / LiquidGlassContainer`, `ESXPCClient.swift / CallServiceObserver.swift / Combine`, `AboutArchitectureBadgesView.swift / AboutArchitectureBadgesView / .architectureName`, `WindowLayout.swift / EqualWidthKey / .reduce()`, `AppDelegate+Actions.swift / AppDelegate+Agent.swift / AgentManageResult`, `.init() / NSCoder / WindowManager.swift`, `ContentView.swift / ContentView / .appSection()`, `.bottomActionBar / .addOtherApps() / .processSelectedPaths()`?**
  _High betweenness centrality (0.150) - this node is a cross-community bridge._
- **Why does `AppState` connect `check-prerequisites.sh / check-prerequisites.sh script / common.sh` to `TouchBarBuilders.swift / AnyObject / NSButton`, `AnyObject / .preview() / MockLockManager`, `SectionHeader.swift / SectionHeader / .body`, `DragHostingView / .mouseDown() / LiquidGlassContainer`, `AppDelegate+MenuBar.swift / .addHeaderMenuItems() / .addMaintenanceMenuItems()`, `ESXPCProtocol.swift / ESXPCProtocol / .notifyBlockedExec()`, `AppListWindowController.swift / AppListWindowController / .createHostingController()`, `AUTH_EXEC PID Assignment / NOTIFY_EXEC Pre/Post Exec Timing / POSIX Liveness & PID Recycling Defense`, `UpdatesSettingsTab.swift / Bool / String`, `ESXPCClient.swift / CallServiceObserver.swift / Combine`, `MainUIButtons.swift / AddAppRow / .body`, `AppDelegate.swift / .manageAgent() / .registerAgentWithoutImmediateLaunch()`, `es_event_exec_t / es_file_t / es_string_token_t`, `CallServiceObserver / .handleNotificationFired() / .init()`?**
  _High betweenness centrality (0.114) - this node is a cross-community bridge._
- **Are the 2 inferred relationships involving `ESManager` (e.g. with `.createClient()` and `.dispatchProcessEvent()`) actually correct?**
  _`ESManager` has 2 INFERRED edges - model-reasoned connections that need verification._
- **Are the 8 inferred relationships involving `AppState` (e.g. with `.body` and `.appSection()`) actually correct?**
  _`AppState` has 8 INFERRED edges - model-reasoned connections that need verification._
- **What connects `NSTouchBarItem.Identifier`, `Notification.Name`, `Notification.Name` to the rest of the system?**
  _242 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `TouchBarBuilders.swift / AnyObject / NSButton` be split into smaller, more focused modules?**
  _Cohesion score 0.055811571940604196 - nodes in this community are weakly interconnected._