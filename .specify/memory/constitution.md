<!--
Sync Impact Report:
- Version change: 1.3.0 → 1.4.0
- List of modified principles:
  - Updated Principle II: Expanded process interception mechanics with Telephony bypass rules.
- Added sections:
  - Telephony Services, Darwin Notification & Incoming Call Bypass Governance
- Removed sections: None
- Follow-up TODOs: None
-->

# AppLocker Project Constitution

## Core Principles

### I. Native Platform First, Observation & Zero Deprecated API Tolerance
All implementations MUST strictly prioritize Apple native platform APIs (Swift Standard Library, SwiftUI, AppKit, CryptoKit, LocalAuthentication, Endpoint Security, OSAllocatedUnfairLock, os.Logger, Observation) over third-party dependencies or redundant custom wrappers.
1. **YAGNI & Linus's Law**: Code additions MUST solve active, immediate requirements without speculative abstractions or unneeded layers of indirection. Refactoring MUST NEVER break or degrade userspace experience, visual integrity (Liquid Glass, `.ultraThinMaterial`), or platform availability checks.
2. **Zero Deprecated API Tolerance**: Implementations MUST NEVER introduce deprecated Apple platform APIs or SDK constants for the current deployment target (macOS 14+). Modern replacements (e.g., `TaskPriority.high` / `TaskPriority.low`, `SMAppService`, `.task(id:)` instead of `.onAppear`) MUST be used exclusively.
3. **Observation over Combine**: Prefer native Observation framework (`@Observable`) or direct `@MainActor` state mutation over legacy Combine `@Published` / `ObservableObject` pipelines. Combine is reserved strictly for complex stream debounce/throttle transformations.

### II. Strict Process Interception, Post-Exec Target Audit Token & PID Recycling Guard
The lifecycle of intercepted processes MUST strictly follow the two-phase kernel contract and Darwin XNU audit token mechanics:
1. `AUTH_EXEC` MUST return `ES_AUTH_RESULT_ALLOW` and record the pending execution path so that the macOS Kernel finishes process instantiation and assigns a valid PID (> 0). In `AUTH_EXEC`, `audit_token_to_pid` returns 0; calling `kill(0, signal)` is strictly prohibited as it targets the entire process group of the caller and disrupts XPC connections.
2. `NOTIFY_EXEC` MUST extract PID and `audit_token_t` from **`message.event.exec.target.pointee.audit_token`** (representing post-exec state after `execve()`) rather than `message.process.audit_token`. This ensures the Darwin XNU incremented `pidversion` matches and prevents false PID recycling aborts.
3. Every POSIX signal invocation (`SIGSTOP`, `SIGCONT`, `SIGKILL`) MUST strictly enforce `guard pid > 0, kill(pid, 0) == 0 else { continue }` to skip dead processes. Before resuming or terminating, compare `audit_token_to_pidversion` via `task_info(TASK_AUDIT_TOKEN)` against the stored audit token to prevent sending signals to a recycled process ID.
4. **Telephony Interception Exception**: When active incoming call state is signaled, verified Apple telephony binaries (`com.apple.mobilephone`, `com.apple.FaceTime`) MUST bypass `SIGSTOP` suspension, preserving user call-alerting UX while maintaining scene-isolated privacy.

### III. Mutual Cryptographic Handshake & Defense in Depth
All inter-process communication between `AppLocker` (Client) and `ESExtension` (Root Daemon) via Mach Service (`com.TranPhuong319.AppLocker.xpc`) MUST enforce bidirectional cryptographic mutual authentication:
1. **Dynamic Caller Validation**: `ESExtension` MUST extract caller audit tokens directly from the kernel to verify executable paths and compute dynamic CDHash matching on-disk binaries before trusting incoming connections.
2. **ECDSA P-256 Nonce Exchange**: Connection authentication MUST require nonces and signatures exchanged and verified via `CryptoKit` (`P256.Signing`). Unauthenticated commands MUST be rejected immediately. Legacy C-style `SecKey` / `Security` framework APIs are prohibited.
3. **Tamper Resistance**: System Extension tampering monitors (`ESTamper`) MUST intercept and deny unauthorized termination signals (`AUTH_SIGNAL`) and unauthorized configuration or binary modifications (`AUTH_FILE`).

### IV. Thread Isolation, Swift 6 Strict Concurrency & Zero Unsafe References
The entire project MUST strictly compile under **Swift 6 Mode** with full data-race safety enforcement:
1. **Main Actor (`@MainActor`)**: `AppState`, `XPCServer`, `BatchAuthWindowController`, `AppListWindowController`, `SettingsWindowController`, `AboutWindowController`, `WindowManager`, and all UI binding states MUST execute exclusively on `@MainActor`.
2. **Background Tasks & Concurrency**: SHA-256 / CDHash calculation, file I/O, `CryptoKit` signature verification, and Endpoint Security event handlers MUST execute in background Tasks or `nonisolated` static helpers. Asynchronous delays MUST use `Task.detached` + `Task.sleep` instead of legacy GCD `asyncAfter`.
3. **Zero `nonisolated(unsafe)` Goal**: Minimize and eliminate the use of `nonisolated(unsafe)`. Strongly prefer **Instance Methods (`self`)** and Dependency Injection over `static` methods and global singletons (`sharedInstanceForCallbacks`) to eliminate mutable global state and ensure 100% data-race safety.
4. **No Main Thread Blocking**: Blocking operations (`Thread.sleep`, `.wait()`, synchronous file reading of large assets) are strictly forbidden on `@MainActor`.

### V. Clean Architecture, Swift API Design Guidelines & Fluent English Phrasing
The codebase is strictly separated into three isolated layers with unified controller lifecycle patterns and standardized Swift API design:
1. **UI & Coordinator Layer (`AppLocker`)**: Handles user interactions, Menu Bar status item, local biometric/passcode prompts (`LocalAuthentication`), settings, and Sparkle updates. All primary window controllers (`AppListWindowController`, `SettingsWindowController`, `AboutWindowController`, `BatchAuthWindowController`) MUST follow the **Persistent Singleton Pattern (`static let shared`)** with pre-warmed hosting layers for instant 0ms presentation.
2. **Privileged System Extension (`ESExtension`)**: Operates as a root daemon handling raw Endpoint Security C callbacks, POSIX signal dispatching, and process freezing via instance-level handlers managed by `ESModularClients`.
3. **Shared Contracts & Models (`Shared`)**: Contains lightweight Codable configuration models (`LockedAppConfig`), strict `@objc` XPC interface protocols (`ESAppProtocol`, `ESXPCProtocol`), and stateless security utilities (`KeychainHelper`, `CDHashHelper`). Overloading optional `@objc` protocol methods with varying parameter counts is prohibited.
4. **Fluent API & Phrasing**: Code must read like grammatical, natural English prose at the call site. Mutating functions MUST use imperative verbs (e.g. `lockSelectedApps()`); pure getters MUST use noun phrases without `get` prefix (e.g. `cdHash(for:)`); action selectors (`@objc func`) MUST name the user intent rather than UI widgets.

### VI. Native macOS Liquid Glass & Human Interface Standards
UI design MUST strictly adhere to macOS Human Interface Guidelines (HIG):
1. Use native macOS container components (`NavigationSplitView`, `Form`, `List`, `.toolbar`) that adopt macOS materials and Liquid Glass automatically. Nested custom glass backgrounds causing visual fragmentation are prohibited.
2. Maintain standard traffic light margins (`~14pt` top padding, `54–68pt` leading inset) to prevent control clipping.
3. Isolate window drag areas to titlebars using `WindowDragArea` (`isMovableByWindowBackground = false`).
4. Support localization via English base static string literals in `Localizable.xcstrings` (dynamic variable keys are prohibited).

### VII. Zero-Tolerance Quality, Unified Logging, Error Handling & Fail-Safe Recovery
Every modification MUST pass strict quality and resilience gates:
1. **SwiftLint Compliance**: Zero errors, zero warnings (`swiftlint lint`). Cyclomatic complexity $\le 10$, function length $< 50$ lines, line length $\le 120$ characters.
2. **Unified Logging**: 100% of telemetry and diagnostic messages MUST go through `Logfile` (`os.Logger`). Direct calls to `print()` or `NSLog()` are strictly prohibited.
3. **Zero Unlogged `try?`**: Never use unlogged `try?` on critical paths (authentication, Keychain, CDHash, I/O). Use strongly typed `LocalizedError` enums.
4. **Watchdog & Fail-Safe**: ESExtension MUST maintain an internal timeout watchdog to prevent permanent system freezes if the Main App is unresponsive. On app termination, pending queues MUST be flushed gracefully.
5. **Strict Resource Teardown**: Observers (`NotificationCenter`), Spotlight queries (`NSMetadataQuery`), timers, and Carbon event handlers MUST be explicitly dismantled in `deinit`.
6. **App Icon Caching**: App icons MUST be retrieved via `AppIconProvider.shared.icon(forPath:size:)` using in-memory `NSCache` to avoid redundant disk reads.
7. **Backward Compatibility**: Refactoring or new features MUST NOT break existing protection rules, IPC contracts, or persistent configuration schemas.

---

## Telephony Services, Darwin Notification & Incoming Call Bypass Governance

- **Darwin Notifications over Private IPC**: State monitoring across security domains MUST prioritize public Darwin Notification APIs (`<notify.h>`) over private framework Mach lookup endpoints (`CoreDuetContext`, `TUCallCenter`) that trigger `NSCocoaErrorDomain Code=4097`.
- **Activity Level State Mapping**: Continuity and call alerting states MUST be monitored via `com.apple.sharing.activity-level-changed` with state `14` (`PhoneCall` / `0x0E`), dispatched on main queue in App and queried directly via `notify_get_state` in Extension.
- **Strict Code Signing Validation for Telephony Bypasses**: Bypassing `SIGSTOP` for incoming calls MUST verify that the target binary satisfies `anchor apple and (identifier "com.apple.mobilephone" or identifier "com.apple.FaceTime")` via `SecStaticCodeCheckValidity`. Unsigned or tampered binaries MUST NOT be bypassed.
- **Biometric Guard on Telephony Policy**: Altering incoming call bypass policy in user preferences MUST require biometric or passcode authentication via `AuthenticationManager.authenticate` before persisting to `config.plist`.

---

## Security & System Extension Governance

- **Kernel Privileges**: Endpoint Security client handles MUST be self-muted appropriately (`es_mute_process`) during initialization to prevent recursive event loops.
- **Biometrics & Authentication**: User authentication MUST be mediated through `AuthenticationManager` using `LAContext` with policy `.deviceOwnerAuthentication` and dispatched to `@MainActor` with `.high` priority.
- **Per-App Grace Period**: The auto-lock timeout logic in `XPCServer` MUST evaluate grace periods against verified application bundle paths before prompting user authentication.
- **Security-Scoped Bookmarks**: Stored user-selected binary and application paths across relaunches MUST use Security-Scoped Bookmarks (`bookmarkData(options:includingResourceValuesForKeys:relativeTo:)`).

---

## Unified Logging & Observability Governance

Logging is categorized into strict process and domain boundaries via `Logfile`:
- **Main App**: `Logfile.app` (Lifecycle/UI), `Logfile.policy` (ConfigStore/Rules), `Logfile.appXPC` (IPC/XPC Server), `Logfile.security` (Keychain/Biometrics).
- **ESExtension**: `Logfile.endpointSecurity` (Interception/Watchdog), `Logfile.esXPC` (Mach Listener), `Logfile.esSecurity` (Handshake/Audit Token).
- Semantic log levels (`.debug`, `.info`, `.notice`, `.warning`, `.error`, `.fault`) MUST be chosen according to the decision matrix defined in project rules.

---

## Quality & Compliance Standards

- **Static Analysis**: `swiftlint lint` MUST run before completing any code changes.
- **Identifier Naming**: All identifiers MUST be $\ge 3$ characters unless overriding private platform selectors explicitly disabled via lint annotations.
- **Closures**: Trailing closure syntax MUST NOT be used when passing multiple closure arguments.
- **No KVC / Selector Reflection**: Declare interface categories in `Bridging-Header.h` instead of runtime reflection (`value(forKey:)`, `performSelector`).

---

## Governance

This Constitution serves as the definitive, supreme technical law for the AppLocker project. All architectural decisions, pull requests, refactorings, and feature additions MUST strictly conform to these articles.

- **Amendments**: Modifying this Constitution requires updating `.specify/memory/constitution.md`, bumping the version according to Semantic Versioning, updating the Sync Impact Report, and securing maintainer approval.
- **Enforcement**: Automated tooling, linting, and agent planning workflows MUST validate compliance with these principles before code execution.

**Version**: 1.4.0 | **Ratified**: 2026-08-21 | **Last Amended**: 2026-09-05
