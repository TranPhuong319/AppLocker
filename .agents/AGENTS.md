# Custom Agent Rules & Architecture Guidelines

Project rules and architecture guidelines are organized into domain-specific modules in [`.agents/rules/`](rules/):

1. **[Clean Architecture & Platform API](rules/architecture.md)**:
   - Ponytail (YAGNI), Linus's Law (never break userspace experience or visual integrity).
   - No Objective-C runtime reflection (KVC / selectors).
   - 3-tier API precedence (Public First $\rightarrow$ Public API + Private ID via Bridging Header $\rightarrow$ Strict Private API Ban).
   - CryptoKit & AppIconProvider caching.
   - Performance & simplicity rules (Swift concurrency over GCD, Combine filter debouncing, resource cleanup).

2. **[Endpoint Security & Low-Level Process Control](rules/endpoint-security.md)**:
   - `AUTH_EXEC` PID assignment timing (`pid = 0`, never call `kill(0, signal)`).
   - `NOTIFY_EXEC` pre-exec vs post-exec audit tokens (`pidversion` increment rule).
   - POSIX liveness & PID recycling defense.
   - Extension safety valve (watchdog) & graceful termination flush.

3. **[Unified Logging & Observability](rules/logging.md)**:
   - Apple Unified Logging (`os.Logger`) subsystem & category hierarchy (`Logfile`).
   - Semantic log level decision matrix (`.debug`, `.info`, `.notice`, `.warning`, `.error`, `.fault`).
   - 5-step recipe for structured logs & privacy interpolation (`privacy: .public`).
   - Strict zero `print()` / `NSLog()` tolerance.

4. **[Swift Concurrency & Thread Isolation](rules/concurrency.md)**:
   - Minimize `nonisolated(unsafe)`, prefer instance methods and dependency injection.
   - `@MainActor` enforcement for UI state models, XPCServer, and window controllers.
   - Background queue isolation for I/O and cryptographic operations.
   - Structured task cancellation tracking.

5. **[Swift Quality, Linting & API Style](rules/swift-quality.md)**:
   - Zero deprecated API tolerance (macOS 14+).
   - Mandatory SwiftLint execution (0 errors, 0 warnings).
   - Function complexity ($\le 10$), body length ($\le 50$), parameters ($\le 5$), line length ($\le 120$).
   - Fluent English API phrasing, verbs vs. nouns, zero `get` prefix, boolean naming.
   - Error handling (zero unlogged `try?`, strongly typed errors).
   - Memory management (`[weak self]` in escaping closures/Tasks).

6. **[Liquid Glass & macOS UI Design](rules/ui-design.md)**:
   - Native macOS Liquid Glass adoption (no custom glass-on-glass layering).
   - Traffic light insets & titlebar drag isolation (`WindowDragArea`).
   - Pure AppKit transparent window skeleton & 100% SwiftUI UI ownership.
   - Optical blur vs. strict clipping scroll patterns.
   - Modern state management (`@Observable` macro over Combine/ObservableObject).

7. **[XPC Resilience & IPC Lifecycle](rules/xpc-and-security.md)**:
   - Explicit XPC protocol definitions (no optional method overloads).
   - Connection auto-reconnect on invalidation, safe proxy error handling.
   - Persistent Security-Scoped Bookmarks & chunked streamed I/O.

8. **[Localization & Communication Guidelines](rules/localization.md)**:
   - English base localization keys with static String literals (clean Xcode string catalog extraction).
   - Primary communication in **Vietnamese (Tiếng Việt)** with standard technical terms in **English**.

9. **[Git Commit Style Guidelines](rules/git-commits.md)**:
   - Conventional commit types (`feat`, `fix`, `perf`, `chore`, `refactor`, `ci`, `docs`, `test`).
   - Subject for users (Sparkle changelog), body for developers.
