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
- **Subject**: for the user, used for Sparkle changelog.
- **Body**: for the coder, explaining what and why.
- **No Class/Function Names**: Do not mention classes or functions in the subject.
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

## Concurrency & Thread Isolation Rules

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

