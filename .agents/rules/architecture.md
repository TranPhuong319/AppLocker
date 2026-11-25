# Clean Architecture & Platform API Guidelines

## Ponytail & Clean Architecture Guidelines

- **Inviolable Rule: Never Break Userspace Experience & Visual Integrity (Linus's Law)**:
  - Code refactoring, optimization, or linting cleanups MUST NEVER degrade, alter, or break the user-facing experience, feature behavior, UI visuals, glass materials, animations, or platform availability checks (`#available`).
  - **Zero Speculative Visual/Feature Stripping**: Do NOT remove visual treatments (e.g. Liquid Glass effects, `.ultraThinMaterial`, custom gradients, window drag isolation, traffic light insets) or platform-specific workarounds under the guise of "simplification" or "clean code".
  - **Strict Behavioral Invariance**: Refactoring must remain strictly internal and behavior-preserving. If a logic branch or check exists to handle an edge case or platform nuance, keep it intact.
- **Lazy Senior Dev Mode (YAGNI)**: Always prefer Apple native platform APIs and Swift standard library over custom helper classes or third-party abstractions.
- **Typed Bridging over Runtime Reflection**:
  - Prefer native Swift platform APIs (e.g. `window.performDrag(with:)`).
  - For non-public SDK properties at the C/ObjC layer (such as `auditToken` on `NSXPCConnection`), declare the interface category in `Bridging-Header.h` for type-safe Swift access (KVC/selector reflection is banned via SwiftLint).
- **Security Framework Validation**: Use Apple's `Security` framework (`SecRequirement`, `SecCodeCheckValidity`, `SecStaticCode`) via `CodeSignatureValidator` and `CDHashHelper` (`cdHash(for:)`) for live XPC/ES signature verification and CDHash extraction.
- **API Precedence: Public First, Public API + Private ID, Private API Ban**:
  - **Tier 1 (Public First - Mandatory Default)**: Prioritize officially documented public Apple platform APIs (Swift Standard Library, SwiftUI, AppKit, Endpoint Security, Security, POSIX Libsystem).
  - **Tier 2 (Fallback: Public API + Undocumented/Private ID via Bridging Header)**: When Apple provides NO public API for a required system behavior (e.g. active incoming calls, appearance/icon-style transitions):
    - Use **Public Apple APIs** (`<notify.h>` in `Bridging-Header.h`, `NSWorkspace.shared.notificationCenter`, `DistributedNotificationCenter`, `UserDefaults`) parameterized with internal notification names/state values (e.g. `"com.apple.sharing.activity-level-changed"` state `14`, `"NSWorkspaceIconAppearanceConfigurationDidChangeNotification"`, `"AppleInterfaceThemeChangedNotification"`).
    - Pair with a **Tier 1 public fallback** when practical (e.g. `NSApplication.didBecomeActiveNotification` gated by a lightweight signature diff).
  - **Tier 3 (Private API Ban)**: Never link Private Frameworks or invoke private symbols dynamically (`NSCocoaErrorDomain Code=4097`, OS update breakage, Gatekeeper/Notarization rejection; enforced via SwiftLint).
- **App Icon Caching & Lazy Refresh**: Load app icons via `AppIconView` or `AppIconProvider.shared` (`loadIcon(for:size:)` / `icon(for:size:)`) to leverage `NSCache`. On global icon-style or appearance changes, clear caches and increment `revision` (`invalidateAllIcons()`) without bulk preloading so off-screen rows reload lazily on scroll via `.task(id:)`.

---

## Performance & Simplicity Rules

- **Swift Concurrency over GCD**:
  - Prefer modern `async/await` and `Task` over legacy GCD queues (`DispatchQueue.global()`). Dedicated GCD queues are reserved for C/Obj-C XPC and Endpoint Security boundaries (`ESXPCClient.xpcQueue`, `ESManager` auth/emergency/background queues) or `notify_register_dispatch` callbacks.
  - Always execute UI updates on `@MainActor`. Heavy operations (CDHash extraction, OSLogStore queries, file I/O) run in background Tasks or `nonisolated static` helpers.
- **Structured Task Debouncing & Fuzzy Search**:
  - Implement search and directory-watcher debouncing via cancelable `@MainActor` `Task` + `try? await Task.sleep(for: .milliseconds(...))` (`AppState`, `LogStore`, `AppScannerService`) rather than `Combine` pipelines.
  - Filter app lists via `FuzzySearch` (`Sequence<InstalledApp>.filter(matching:)`) using whitespace-trimmed tokenized scoring.
- **Strict Resource & Observer Cleanup**:
  - All `NotificationCenter` observers, `NSMetadataQuery` instances, `DispatchSourceFileSystemObject` watchers, and Carbon Event Handlers (`InstallEventHandler`) MUST be explicitly torn down in `deinit`.
  - Clear `invalidationHandler` and `interruptionHandler` on `NSXPCConnection` before invoking `.invalidate()` to prevent recursive invalidation loops.
- **Native Platform First & YAGNI**:
  - Always prefer Apple native APIs (`NSAlert.beginSheetModal` via `AlertShow`, Swift Standard Library, `Security`) over custom wrapper abstractions.
  - Keep codebase simple and lean. Avoid speculative features or unnecessary protocol indirections unless required for previews/tests.
