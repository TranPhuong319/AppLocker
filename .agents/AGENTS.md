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

- **Lazy Senior Dev Mode (YAGNI)**: Always prefer Apple native platform APIs and Swift standard library over custom helper classes or third-party abstractions.
- **CryptoKit**: Use `CryptoKit` (`P256.Signing`) for all EC key generation, ECDSA signing, and signature verification. Avoid legacy C-style `SecKey` / `Security` framework APIs.
- **App Icon Caching**: Always load app icons via `AppIconProvider.shared.icon(forPath:size:)` to leverage the in-memory `NSCache` system and avoid redundant disk read operations.

---

## Endpoint Security & POSIX Signal Gotchas (CRITICAL)

### 1. Kernel PID Assignment Timing
- In `AUTH_EXEC` events, macOS Kernel has not completed process instantiation. `audit_token_to_pid` returns **PID = 0**.
- **DO NOT** invoke `kill(0, signal)`. In POSIX/macOS C, `kill(0, signal)` sends the signal to **the entire process group of the caller (`ESExtension`)**, which disrupts XPC connection (`NSCocoaErrorDomain Code=4097`).

### 2. Standard Process Interception Pattern
- **`AUTH_EXEC`**: Mark pending path in `pendingVerificationPaths` and return `ES_AUTH_RESULT_ALLOW` so the Kernel creates the process and assigns a real PID.
- **`NOTIFY_EXEC`**: Read the real PID (> 0) from `message.process.audit_token`, execute `kill(targetPid, SIGSTOP)` to freeze the target process in `STOPPED` state, and notify `AppLocker` with the valid PID (> 0).
- **Safety Guard**: Always enforce `guard pid > 0 else { continue }` before any `kill(pid, SIGCONT)` or `kill(pid, SIGKILL)` call.

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
  - `XPCServer`, `BatchAuthWindowController`, `AppState`, and all `@Published` properties MUST be executed on `@MainActor`.
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
  - Wrap top header views in `WindowDragArea` using `NSSelectorFromString("performWindowDragWithEvent:")` so dragging is strictly isolated to the titlebar region.
- **AppKit Skeleton with SwiftUI Hosting**:
  - When wrapping SwiftUI views in AppKit `NSWindowController` / `NSWindow`, enable
    `sceneBridgingOptions = [.toolbars, .title]` on `NSHostingController` (macOS 14+) AND assign an `NSToolbar`
    instance (`window.toolbar = NSToolbar(...)`) at the AppKit level so SwiftUI can bridge window title, toolbar
    items, and native `NavigationSplitView` sidebar toggle controls into the window automatically.
- **Scrollable Header Optical Blur vs. Strict Clipping Patterns**:
  - *Pattern A (Optical Blur Behind Header)*: Use `ScrollView { ... }.safeAreaInset(edge: .top, spacing: 0) { headerView }` where `headerView` has `.background(Rectangle().fill(.ultraThinMaterial.opacity(0.6)).ignoresSafeArea(edges: .top))`. Note: in this pattern, content scrolls continuously underneath the header all the way to `y = 0`.
  - *Pattern B (Clean Bound / Zero Collision)*: Use `VStack(spacing: ...) { headerView; ScrollView { ... }.clipped() }` to strictly confine the scrolling area below the header without content peeking into the titlebar or traffic lights.

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
