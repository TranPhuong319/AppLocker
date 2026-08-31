<!--
Sync Impact Report:
- Version change: 1.1.0 → 1.2.0
- List of modified principles:
  - Updated Principle I: Native Platform First, Observation & Zero Deprecated API Tolerance
  - Updated Principle IV: Thread Isolation, Swift 6 Strict Concurrency & Zero Unsafe References
  - Updated Principle V: Clean Architecture, Instance Methods & Dependency Injection
- Added sections: None
- Removed sections: None
- Follow-up TODOs: None
-->

# AppLocker Project Constitution

## Core Principles

### I. Native Platform First, Observation & Zero Deprecated API Tolerance
All implementations MUST strictly prioritize Apple native platform APIs (Swift Standard Library, SwiftUI, AppKit, CryptoKit, LocalAuthentication, Endpoint Security, OSAllocatedUnfairLock, os.Logger, Observation) over third-party dependencies or redundant custom wrappers.
1. **YAGNI**: Code additions MUST solve active, immediate requirements without speculative abstractions or unneeded layers of indirection.
2. **Zero Deprecated API Tolerance**: Implementations MUST NEVER introduce deprecated Apple platform APIs or SDK constants for the current deployment target (macOS 14+). Modern replacements (e.g., `TaskPriority.high` / `TaskPriority.low`, `SMAppService`, `.task(id:)` instead of `.onAppear`) MUST be used exclusively.
3. **Observation over Combine**: Prefer native Observation framework (`@Observable`) or direct `@MainActor` state mutation over legacy Combine `@Published` / `ObservableObject` pipelines.

### II. Strict Process Interception & POSIX Signal Safety
The lifecycle of intercepted processes MUST strictly follow the two-phase kernel contract:
1. `AUTH_EXEC` MUST return `ES_AUTH_RESULT_ALLOW` and record the pending execution path so that the macOS Kernel finishes process instantiation and assigns a valid PID (> 0).
2. `NOTIFY_EXEC` MUST read the verified PID (> 0) from `message.process.audit_token`, verify authorization status against locked application rules, immediately freeze the process using `kill(targetPid, SIGSTOP)`, and notify the main application over XPC.
3. Every POSIX signal invocation (`SIGSTOP`, `SIGCONT`, `SIGKILL`) MUST strictly enforce `guard pid > 0 else { return }`. Invoking `kill(0, signal)` is strictly prohibited as it targets the entire process group of the caller and disrupts XPC connections.

### III. Mutual Cryptographic Handshake & Defense in Depth
All inter-process communication between `AppLocker` (Client) and `ESExtension` (Root Daemon) via Mach Service (`com.TranPhuong319.AppLocker.xpc`) MUST enforce bidirectional cryptographic mutual authentication:
1. **Dynamic Caller Validation**: `ESExtension` MUST extract caller audit tokens directly from the kernel to verify executable paths and compute dynamic CDHash matching on-disk binaries before trusting incoming connections.
2. **ECDSA P-256 Nonce Exchange**: Connection authentication MUST require nonces and signatures exchanged and verified via `CryptoKit` (`P256.Signing`). Unauthenticated commands MUST be rejected immediately.
3. **Tamper Resistance**: System Extension tampering monitors (`ESTamper`) MUST intercept and deny unauthorized termination signals (`AUTH_SIGNAL`) and unauthorized configuration or binary modifications (`AUTH_FILE`).

### IV. Thread Isolation, Swift 6 Strict Concurrency & Zero Unsafe References
The entire project MUST strictly compile under **Swift 6 Mode** with full data-race safety enforcement:
1. **Main Actor (`@MainActor`)**: `AppState`, `XPCServer`, `BatchAuthWindowController`, `AppListWindowController`, `SettingsWindowController`, `AboutWindowController`, `WindowManager`, and all UI binding states MUST execute exclusively on `@MainActor`.
2. **Background Tasks & Concurrency**: SHA-256 / CDHash calculation, file I/O, `CryptoKit` signature verification, and Endpoint Security event handlers MUST execute in background Tasks or `nonisolated` static helpers. Asynchronous delays MUST use `Task.detached` + `Task.sleep` instead of legacy GCD `asyncAfter`.
3. **Zero `nonisolated(unsafe)` Goal**: Minimize and eliminate the use of `nonisolated(unsafe)`. Strongly prefer **Instance Methods (`self`)** and Dependency Injection over `static` methods and global singletons (`sharedInstanceForCallbacks`) to eliminate mutable global state and ensure 100% data-race safety.
4. **No Main Thread Blocking**: Blocking operations (`Thread.sleep`, `.wait()`, synchronous file reading of large assets) are strictly forbidden on `@MainActor`.

### V. Clean Architecture, Instance Methods & Dependency Injection
The codebase is strictly separated into three isolated layers with unified controller lifecycle patterns:
1. **UI & Coordinator Layer (`AppLocker`)**: Handles user interactions, Menu Bar status item, local biometric/passcode prompts (`LocalAuthentication`), settings, and Sparkle updates. All primary window controllers (`AppListWindowController`, `SettingsWindowController`, `AboutWindowController`, `BatchAuthWindowController`) MUST follow the **Persistent Singleton Pattern (`static let shared`)** with pre-warmed hosting layers for instant 0ms presentation.
2. **Privileged System Extension (`ESExtension`)**: Operates as a root daemon handling raw Endpoint Security C callbacks, POSIX signal dispatching, and process freezing via instance-level handlers managed by `ESModularClients`.
3. **Shared Contracts & Models (`Shared`)**: Contains lightweight Codable configuration models (`LockedAppConfig`), strict `@objc` XPC interface protocols (`ESAppProtocol`, `ESXPCProtocol`), and stateless security utilities (`KeychainHelper`, `CDHashHelper`). Overloading optional `@objc` protocol methods with varying parameter counts is prohibited.

### VI. Native macOS Liquid Glass & Human Interface Standards
UI design MUST strictly adhere to macOS Human Interface Guidelines (HIG):
1. Use native macOS container components (`NavigationSplitView`, `Form`, `List`, `.toolbar`) that adopt macOS materials and Liquid Glass automatically. Nested custom glass backgrounds causing visual fragmentation are prohibited.
2. Maintain standard traffic light margins (`~14pt` top padding, `54–68pt` leading inset) to prevent control clipping.
3. Isolate window drag areas to titlebars using `WindowDragArea` (`isMovableByWindowBackground = false`).
4. Support localization via English base static string literals in `Localizable.xcstrings` (dynamic variable keys are prohibited).

### VII. Zero-Tolerance Quality, Unified Logging & Resource Integrity
Every modification MUST pass strict quality gates:
1. **SwiftLint Compliance**: Zero errors, zero warnings (`swiftlint lint`). Cyclomatic complexity $\le 10$, function length $< 50$ lines, line length $\le 120$ characters.
2. **Unified Logging**: 100% of telemetry and diagnostic messages MUST go through `Logfile` (`os.Logger`). Direct calls to `print()` or `NSLog()` are strictly prohibited.
3. **Strict Resource Teardown**: Observers (`NotificationCenter`), Spotlight queries (`NSMetadataQuery`), timers, and Carbon event handlers MUST be explicitly dismantled in `deinit`.
4. **App Icon Caching**: App icons MUST be retrieved via `AppIconProvider.shared.icon(forPath:size:)` using in-memory `NSCache` to avoid redundant disk reads.
5. **Backward Compatibility**: Refactoring or new features MUST NOT break existing protection rules, IPC contracts, or persistent configuration schemas.

---

## Security & System Extension Governance

- **Kernel Privileges**: Endpoint Security client handles MUST be self-muted appropriately (`es_mute_process`) during initialization to prevent recursive event loops.
- **Biometrics & Authentication**: User authentication MUST be mediated through `AuthenticationManager` using `LAContext` with policy `.deviceOwnerAuthentication` and dispatched to `@MainActor` with `.high` priority.
- **Per-App Grace Period**: The auto-lock timeout logic in `XPCServer` MUST evaluate grace periods against verified application bundle paths before prompting user authentication.

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

---

## Governance

This Constitution serves as the definitive, supreme technical law for the AppLocker project. All architectural decisions, pull requests, refactorings, and feature additions MUST strictly conform to these articles.

- **Amendments**: Modifying this Constitution requires updating `.specify/memory/constitution.md`, bumping the version according to Semantic Versioning, updating the Sync Impact Report, and securing maintainer approval.
- **Enforcement**: Automated tooling, linting, and agent planning workflows MUST validate compliance with these principles before code execution.

**Version**: 1.2.0 | **Ratified**: 2026-08-21 | **Last Amended**: 2026-08-31
