# Custom Agent Rules & Architecture Guidelines

## Git Commit Style
Always follow this commit message format and guidelines when making commits:

### Commit Types (Choose 1)
- `feat(scope)`: User-facing change (new feature)
- `fix(scope)`: User-facing bug fix
- `perf(scope)`: User-facing performance improvement
- `chore(scope)`: Internal / build / tooling
- `refactor(scope)`: Code structure, no user change
- `ci(scope)`: Workflow / github actions
- `docs(scope)`: Documentation only
- `test(scope)`: Tests only

### Format
```
<type>(<scope>): <user-facing summary>

<developer-facing details>
```

### Rules
- **Subject**: For the user, used for Sparkle changelog.
- **Body**: For the developer, explaining what and why.
- **No Class/Function Names**: Do not mention classes or functions in the subject line.
- **Sparkle Changelog**: Only `feat`, `fix`, and `perf` types appear in the Sparkle changelog.

---

## Ponytail & Clean Architecture Guidelines

- **Inviolable Rule: Never Break Userspace Experience & Visual Integrity (Linus's Law)**:
  - Code refactoring, optimization, or linting cleanups MUST NEVER degrade, alter, or break the user-facing experience, feature behavior, UI visuals, glass materials, animations, or platform availability checks (`#available`).
  - **Zero Speculative Visual/Feature Stripping**: Do NOT remove visual treatments (e.g. Liquid Glass effects, `.ultraThinMaterial`, custom gradients, window drag isolation, traffic light insets) or platform-specific workarounds under the guise of "simplification" or "clean code".
  - **Strict Behavioral Invariance**: Refactoring must remain strictly internal and behavior-preserving. If a logic branch or check exists to handle an edge case or platform nuance, keep it intact.
- **Lazy Senior Dev Mode (YAGNI)**: Always prefer Apple native platform APIs and Swift standard library over custom helper classes or third-party abstractions.
- **No KVC / Selector Reflection**:
  - Do NOT use Objective-C runtime reflection (`value(forKey:)`, `setValue(_:forKey:)`, `NSSelectorFromString`, `performSelector`) to access SDK properties or private methods.
  - Always prefer native Swift platform APIs (e.g. `window.performDrag(with:)`).
  - When accessing non-public SDK properties that exist at the C/ObjC layer (such as `auditToken` on `NSXPCConnection`), declare the interface category in the target's `Bridging-Header.h` so the Swift Clang Importer provides first-class, type-safe native Swift syntax with zero runtime reflection overhead.
- **CryptoKit**: Use `CryptoKit` (`P256.Signing`) for all EC key generation, ECDSA signing, and signature verification. Avoid legacy C-style `SecKey` / `Security` framework APIs.
- **App Icon Caching**: Always load app icons via `AppIconProvider.shared.icon(forPath:size:)` to leverage the in-memory `NSCache` system and avoid redundant disk read operations.

---

## Endpoint Security & POSIX Signal Gotchas (CRITICAL)

### 1. Kernel PID Assignment Timing
- In `AUTH_EXEC` events, macOS Kernel has not completed process instantiation. `audit_token_to_pid` returns **PID = 0**.
- **DO NOT** invoke `kill(0, signal)`. In POSIX/macOS C, `kill(0, signal)` sends the signal to **the entire process group of the caller (`ESExtension`)**, which disrupts XPC connection (`NSCocoaErrorDomain Code=4097`).

### 2. Pre-Exec vs Post-Exec Audit Token (`NOTIFY_EXEC`)
- In `NOTIFY_EXEC` events (`es_event_exec_t`):
  - `message.process.audit_token` represents the **pre-exec** process state (before binary loading).
  - `message.event.exec.target.audit_token` represents the **post-exec** process state (after `execve()` has completed).
  - **`pidversion` Increment Rule**: Darwin XNU Kernel increments `pidversion` by 1 upon every successful `execve()`.
  - **MANDATORY**: Always extract PID and `audit_token_t` from **`message.event.exec.target.pointee.audit_token`** when registering pending processes. Using `message.process` will cause `pidversion` mismatch (`expected != current`) and falsely trigger PID recycling aborts.

### 3. POSIX Liveness & PID Recycling Guard
- **Liveness Check**: Always enforce `guard pid > 0, kill(pid, 0) == 0 else { continue }` before issuing any signal to safely skip dead or terminated processes.
- **PID Recycling Defense**: Compare `audit_token_to_pidversion` of the currently running process (via `task_info(TASK_AUDIT_TOKEN)`) with the stored `audit_token_t` from `NOTIFY_EXEC` before invoking `kill(pid, SIGCONT)` or `kill(pid, SIGKILL)` to prevent sending signals to a recycled process ID.

---

## Unified Logging & Observability Guidelines

### 1. Logger Taxonomy & Subsystem Architecture
AppLocker uses Apple's native Unified Logging (`os.Logger`) organized into a strict two-tier hierarchy: **Subsystem (Process Boundary) $\rightarrow$ Category (Functional Layer)**.

```swift
public enum Logfile {
    // MARK: - Main App Subsystem (com.TranPhuong319.AppLocker)
    public static let app = Logger(subsystem: "com.TranPhuong319.AppLocker", category: "App")
    public static let policy = Logger(subsystem: "com.TranPhuong319.AppLocker", category: "Policy")
    public static let appXPC = Logger(subsystem: "com.TranPhuong319.AppLocker", category: "XPC")
    public static let security = Logger(subsystem: "com.TranPhuong319.AppLocker", category: "Security")

    // MARK: - ESExtension Subsystem (com.TranPhuong319.AppLocker.ESExtension)
    public static let endpointSecurity = Logger(subsystem: "com.TranPhuong319.AppLocker.ESExtension", category: "EndpointSecurity")
    public static let esXPC = Logger(subsystem: "com.TranPhuong319.AppLocker.ESExtension", category: "XPC")
    public static let esSecurity = Logger(subsystem: "com.TranPhuong319.AppLocker.ESExtension", category: "Security")
}
```

### 2. Semantic Log Level Decision Matrix

| Log Level | Purpose & Retention | When to Use |
|---|---|---|
| **`.debug`** | Verbose / High-frequency trace. Not persisted to disk in Release builds unless live streamed. | Benchmark timings, loop steps, debounce ticks, raw payload dumps, allowlist matches, non-critical cache/IO status. |
| **`.info`** | Operational telemetry & state transitions. Persisted in memory / transient disk. | App/service startup milestones, config load counts, XPC connection established, updater checking. |
| **`.notice`** (or `.log`) | **High-value business & security decisions**. Standard level visible in Console.app by default. | App execution blocked, user batch auth approved/cancelled, protection toggled, ES clients active. |
| **`.warning`** | Recoverable anomalies, non-fatal errors, timeouts, fallback branches. | Timeout reached (auto cancel), AppleScript fallback for file move, unauthorized main app exit detected. |
| **`.error`** | Operation failures, unexpected exceptions, syscall errors. | File write failure, failed to send SIGKILL/SIGCONT, XPC proxy acquisition failed, extension install failed. |
| **`.fault`** | Invariant violations, active tampering, critical corruption. | Binary CDHash mismatch between runtime process and disk, safety valve hard deadline exceeded. |

### 3. Step-by-Step Recipe: How to Write Logs for Any Code/Feature

Whenever adding logging to any function, handler, or component, strictly follow these 5 steps:

1. **Step 1: Choose the Matching Logger Domain**:
   - UI / App Lifecycle / Updater $\rightarrow$ `Logfile.app`
   - Policy / Config Store / Rules $\rightarrow$ `Logfile.policy`
   - Main App IPC / XPC Server & Client $\rightarrow$ `Logfile.appXPC`
   - Main App Keychain & Touch ID $\rightarrow$ `Logfile.security`
   - Endpoint Security Interception / Watchdog $\rightarrow$ `Logfile.endpointSecurity`
   - ESExtension IPC / Mach Listener $\rightarrow$ `Logfile.esXPC`
   - ESExtension Signature / Caller Validation $\rightarrow$ `Logfile.esSecurity`

2. **Step 2: Select the Exact Semantic Level**:
   - Never default to `.log(...)` blindly. Use `.debug` for internal logic, `.info` for transitions, `.notice` for security actions, `.warning` for fallbacks, `.error` for failures, `.fault` for tampering.

3. **Step 3: Structure the Message with a Tag/Prefix**:
   - Format: `[Component/Tag] Action description - Details`
   - Example: `Logfile.policy.debug("[ConfigStore] Saved \(count, privacy: .public) apps to disk")`

4. **Step 4: Explicit Privacy Interpolation for Diagnostic IDs**:
   - Mark non-sensitive system identifiers as `privacy: .public` (e.g., PIDs, paths, counts, durations, status codes) so they are readable in Console.app and `log stream` without being redacted into `<private>`.

5. **Step 5: Zero `print()` / `NSLog()` Tolerance**:
   - Absolutely NEVER use `print()` or `NSLog()`. All logging MUST go through `Logfile`.

### 4. Concrete Code Examples

```swift
// Example 1: High-Frequency / Timing Debug Trace
Logfile.security.debug("[Keychain] Ephemeral EC keys generated in \(elapsedMs, format: .fixed(precision: 1))ms")

// Example 2: Normal Lifecycle State Transition Info
Logfile.app.info("[Bootstrap] AppLocker v\(Bundle.main.fullVersion, privacy: .public) starting...")

// Example 3: High-Value Security Notice
Logfile.appXPC.notice("[Auth] Batch authentication approved for \(approvedPIDs.count, privacy: .public) application(s)")

// Example 4: Recoverable Fallback / Anomaly Warning
Logfile.app.warning("[Installer] Move to /Applications failed via FileManager: \(error.localizedDescription), falling back to AppleScript")

// Example 5: Syscall / Operation Error
Logfile.endpointSecurity.error("[Process] Failed to send SIGKILL to PID \(pid, privacy: .public): errno \(errno, privacy: .public)")

// Example 6: Security Violation / System Tampering Fault
Logfile.esSecurity.fault("[Auth] CDHash mismatch between running process and disk binary for PID \(pid, privacy: .public)!")
```

---

## Concurrency & Thread Isolation Rules

- **Minimize `nonisolated(unsafe)` & Prefer Instance Methods**:
  - Minimize the usage of `nonisolated(unsafe)` as much as possible. Only use it as a last resort when no safer concurrency solution exists without disrupting existing features or code stability.
  - Strongly prefer **Instance Methods (`self`)** and Dependency Injection over `static` methods and global singleton references (e.g. `sharedInstanceForCallbacks`). This ensures clean actor/thread ownership, eliminates global mutable state, and guarantees full Swift 6 Strict Concurrency safety.
- **Main Thread (`@MainActor`)**:
  - `XPCServer`, `BatchAuthWindowController`, `AppState`, and all `@Observable` UI state models MUST be executed on `@MainActor`.
  - All UI state changes and window operations must originate from `@MainActor` methods.
- **Background Queues**:
  - SHA256 computation, file I/O, `CryptoKit` signatures, and ES event processing MUST run on background queues (`authorizationProcessingQueue`, `xpcQueue`).
  - NEVER perform blocking thread synchronization (`Thread.sleep`, `.wait()`) on `@MainActor`.
  - XPC callbacks received on background queues must dispatch to `@MainActor` via `DispatchQueue.main.async`.

---

## XPC Protocol Design Rules

- **No Optional Method Overloading**: Avoid creating optional `@objc` method overloads with different parameter counts in `NSXPCInterface` protocols (e.g. `notifyBlockedExec(name:path:sha:)` vs `notifyBlockedExec(name:path:sha:pid:)`). Objective-C selector resolution may dispatch to the wrong fallback method and drop parameters.
- Keep XPC protocol definitions explicit, strict, and unambiguous.

---

## Swift Quality & Linting Rules

- **Zero Deprecated API Tolerance**: ALWAYS verify that any Apple platform API, SDK enum case, or Swift standard library feature is NOT deprecated for the current deployment target (macOS 14+). Always use the modern, active replacement (e.g. `TaskPriority.high` instead of `.userInteractive`, `.task` instead of `.onAppear`, `SMAppService` instead of `SMJobBless`).
- **Mandatory SwiftLint Execution**: ALWAYS execute `swiftlint lint` after any code modification or refactoring to verify 0 errors and 0 warnings before concluding work. Fix any lint issues immediately.
- **Type Nesting**: Do NOT nest types (structs/enums/classes) more than 1 level deep (e.g. use `WindowLayout.AddApp` instead of `WindowLayout.Sheet.AddApp`).
- **Cyclomatic Complexity**: Keep function cyclomatic complexity $\le 10$. Extract helper methods for complex branching or dispatch logic.
- **Function Body Length & Parameters**: Keep function bodies under 50 lines and parameters $\le 5$. Group parameters into structs (e.g. `BlockedExecContext`) when exceeding 5 parameters.
- **Line Length**: Limit lines to $\le 120$ characters. Format function calls, declarations, and log messages across multiple lines or use multiline strings.
- **Identifier Naming**: All variable and function names MUST be $\ge 3$ characters long. Use `// swiftlint:disable:next identifier_name` strictly when overriding AppKit/macOS private selectors (e.g. `_registerWithIntentsFramework()`).
- **Trailing Closures**: Do NOT use trailing closure syntax when passing multiple closure arguments (e.g. for `Button(action:label:)`, explicitly pass `label: { ... }`).

---

## Swift Naming & Fluent English API Guidelines

- **Fluent English Phrasing (Clarity at Point of Use)**:
  - Code must read like grammatical, natural English prose at the call site (e.g. `fuzzyMatch(tokens, in: app.name)` rather than `fuzzyMatch(tokens: tokens, target: app.name)`).
  - Use appropriate English prepositions (`in:`, `for:`, `to:`, `from:`, `with:`, `by:`) for secondary argument labels.
  - Omit the first argument label (`_`) when the function base name and first parameter form a natural phrase or when the first parameter is the obvious primary subject (e.g. `contains(_:)`, `icon(forPath:size:)`).
- **Verbs vs. Nouns (Side Effects vs. Pure Getters)**:
  - **Functions with Side Effects**: Name with imperative verb phrases (e.g. `lockSelectedApps()`, `save()`, `connect()`, `dismissAddAppSheet()`, `clearDeleteQueue()`).
  - **Pure Getters / Non-Mutating Value Return**: Name with noun phrases (e.g. `cdHash(for:)`, `processPath(for:)`, `selfAuditToken()`).
  - **Zero `get` Prefix**: Do NOT prefix pure getter functions with `get...` (use `auditToken(for:)` instead of `getCurrentAuditToken(for:)`, `cdHash(for:)` instead of `getCDHash(for:)`).
- **Boolean Properties & Methods**:
  - Name as assertions using `is`, `has`, `can`, `should` (e.g. `isLocked`, `hasAvailableUpdate`, `shouldEnable`, `isMock`).
- **UI Actions & Selector Methods (`@objc func`)**:
  - Name after the **intended action or user intent**, NEVER after the UI widget type (e.g. use `lockSelectedApps()`, `chooseCustomApp()`, `showDeleteQueueSheet()` instead of `lockButton()`, `addAnotherApp()`, `deleteQueuePopup()`).
- **Standard English Grammar & Pluralization**:
  - Adhere to correct English plural forms and adjective rules (e.g. `addOtherApps` instead of `addOthersApp`, `searchTextUnlockableApps` instead of `searchTextUnlockaleApps`).
- **Clarity Over Brevity**:
  - Avoid cryptic truncations. Only use universally accepted industry acronyms (e.g. `PID`, `URL`, `XPC`, `ID`, `CDHash`).

---

## Performance & Simplicity Rules

- **Swift Concurrency over GCD**:
  - Prefer modern `async/await` and `Task` over legacy `DispatchQueue.global().async` / `DispatchQueue.main.async`.
  - Always execute UI updates on `@MainActor` and compute heavy operations (cdhash extraction, file I/O) in background Tasks or `nonisolated static` helpers.
- **Combine & Filter Debouncing**:
  - Use `RunLoop.main` or `DispatchQueue.main` for Combine search filter `.debounce` pipelines to keep publisher streams isolated to the main actor without cross-thread hops.
  - Use standardized `String.normalized` trimming whitespaces/newlines for instant, zero-alloc search matching.
- **Strict Resource & Observer Cleanup**:
  - All `NotificationCenter` observers, `NSMetadataQuery` instances, and Carbon Event Handlers (`InstallEventHandler`) MUST be explicitly torn down in `deinit`.
  - Clear `invalidationHandler` and `interruptionHandler` on `NSXPCConnection` before invoking `.invalidate()` to prevent recursive invalidation loops.
- **Native Platform First & YAGNI**:
  - Always prefer Apple native APIs (e.g. `NSAlert.beginSheetModal`, Swift Standard Library `UInt8.random`, `CryptoKit`) over custom wrapper abstractions.
  - Keep codebase simple and lean. Avoid speculative features or unnecessary protocol indirections unless required for previews/tests.

---

## Liquid Glass & macOS UI Design Guidelines

- **No Custom Glass-on-Glass Layering**:
  - Rely on Apple native components (`NavigationSplitView`, `NavigationStack`, `Form`, `List`, `.toolbar`) to adopt macOS Liquid Glass material automatically.
  - Avoid wrapping custom background modifiers (`.liquidGlassBackground`, `.liquidGlassCard`) over standard containers to prevent visual fragmentation and dark box artifacts.
- **Traffic Light Margin & Inset**:
  - Always provide top padding (`~14pt`) and leading inset (`54–68pt`) in top window headers to cleanly isolate traffic light buttons (close/minimize/zoom) from clipping window corners or content text.
- **Titlebar Drag Isolation**:
  - Enforce `isMovableByWindowBackground = false` on `NSWindow` instances.
  - Wrap top header views in `WindowDragArea` using native `window.performDrag(with:)` so dragging is strictly isolated to the titlebar region.
- **AppKit Skeleton with SwiftUI Hosting**:
  - When wrapping SwiftUI views in AppKit `NSWindowController` / `NSWindow`, enable
    `sceneBridgingOptions = [.toolbars, .title]` on `NSHostingController` (macOS 14+) AND assign an `NSToolbar`
    instance (`window.toolbar = NSToolbar(...)`) at the AppKit level so SwiftUI can bridge window title, toolbar
    items, and native `NavigationSplitView` sidebar toggle controls into the window automatically.
- **Scrollable Header Optical Blur vs. Strict Clipping Patterns**:
  - *Pattern A (Optical Blur Behind Header)*: Use `ScrollView { ... }.safeAreaInset(edge: .top, spacing: 0) { headerView }` where `headerView` has `.background(Rectangle().fill(.ultraThinMaterial.opacity(0.6)).ignoresSafeArea(edges: .top))`. Note: in this pattern, content scrolls continuously underneath the header all the way to `y = 0`.
  - *Pattern B (Clean Bound / Zero Collision)*: Use `VStack(spacing: ...) { headerView; ScrollView { ... }.clipped() }` to strictly confine the scrolling area below the header without content peeking into the titlebar or traffic lights.

---

## XPC Resilience & IPC Lifecycle Rules

- **Connection Invalidation & Auto-Reconnect**:
  - Never retain or reuse an `NSXPCConnection` once invalidated. Reset internal connection variables to `nil` in `invalidationHandler` so the next call lazily reinstantiates a healthy connection.
  - Clear `interruptionHandler` and `invalidationHandler` before calling `.invalidate()` to avoid recursive or dangling invalidation events.
- **Safe Proxy Invocations**:
  - Always invoke remote proxies via `remoteObjectProxyWithErrorHandler:` or `synchronousRemoteObjectProxyWithErrorHandler:` to catch communication failures and timeouts proactively instead of failing silently.

---

## Fail-Safe & Process Recovery Rules

- **Watchdog / Extension Safety Valve**:
  - ESExtension must maintain an internal timeout/watchdog for pending blocked processes. If the Main App crashes or does not respond within the safety window (e.g. 30–60s), unfreeze or safely handle pending processes to prevent permanent system freeze.
- **Graceful Termination & Pending Queue Flush**:
  - When Main App terminates (`applicationWillTerminate` or receiving termination signal), notify the Extension to flush pending queues and resume paused processes if appropriate.

---

## Error Handling & Silent Failure Ban

- **Zero Unlogged `try?` on Critical Paths**:
  - Never use `try?` on authentication, I/O, Keychain, CDHash extraction, or XPC serialization without a clear fallback and logging.
  - When `try?` is used for non-critical fallback branches, always log the result or reason at `.debug` or `.warning` level.
- **Strongly Typed App Errors**:
  - Use strongly typed error enums conforming to `LocalizedError` / `CustomNSError` for structured domain errors rather than generic String errors.

---

## Memory Management & Task Lifetime Rules

- **Escaping Closures & Retain Cycles**:
  - Always use `[weak self]` in escaping closures, long-running asynchronous `Task` blocks, and notification observers referencing `NSWindowController`, `NSViewController`, or `AppState`.
- **Structured Task Cancellation**:
  - Hold references to long-running asynchronous tasks (`Task<Void, Never>?`) and explicitly cancel them (`task?.cancel()`) in `deinit` or during view/window teardown.

---

## Security-Scoped Bookmarks & File Access Integrity

- **Persistent User-Selected Paths**:
  - Use Security-Scoped Bookmarks (`bookmarkData(options:includingResourceValuesForKeys:relativeTo:)`) when storing custom user-selected binary or application paths across application relaunches.
- **Safe Streamed I/O**:
  - For large file inspection and hashing, stream chunks through `FileHandle` / memory mapping rather than reading multi-gigabyte binary files into RAM at once.

---

## Modern State Management Rules

- **Observation Framework over Combine for UI State**:
  - For macOS 14+ view state models, prefer the Swift `@Observable` macro over `ObservableObject` / `@Published` to reduce boilerplate and optimize granular view re-rendering.
  - Reserve `Combine` strictly for complex asynchronous stream transformations (e.g. `.debounce`, `.throttle`, `.combineLatest`).

---

## Localization & String Catalog Guidelines

- **English Base Keys & Static String Literals**:
  - Always write base localization keys in **English** using explicit, static String literals (e.g. `return "General"` instead of `LocalizedStringKey(rawValue)`).
  - Do NOT pass dynamic variables into `LocalizedStringKey(rawValue)` or `String(localized: variable)`. Xcode's static compiler extractor cannot trace dynamic variables and will mark string keys as `stale` in `Localizable.xcstrings`.
  - For enums requiring localized display names, use explicit `switch self` statements returning String literals (e.g. `case .general: return "General"`).
  - Strings wrapped inside conditional compilation blocks (e.g. `#if DEBUG`) might be marked as `stale` during standard Release builds by Xcode's static extractor. Remove `"extractionState": "stale"` if the string is intentionally kept for DEBUG builds.

---

## Language & Communication Style Guidelines

- **Primary Language**: Always communicate, explain, and interact with the user in **Vietnamese (Tiếng Việt)**.
- **Technical Terms**: Keep industry-standard, framework, and programming terminology in **English (Thuật ngữ Tiếng Anh)** (e.g., *deployment target, view modifier, content transition, background tasks, thread isolation, dependency injection, runtime checks, audit token, mutual authentication*).
