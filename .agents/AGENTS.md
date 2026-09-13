# Custom Agent Rules & Architecture Guidelines

## Operational Safety & Rule Governance

- **Rule Size Ceiling ($\le 12,000$ chars/bytes)**: Every rule file in `.agents/rules/` and `AGENTS.md` must stay strictly under 12,000 characters/bytes. Decompose any rule approaching this limit into focused domain sub-modules.
- **On-Demand Rule Loading**: When executing a task, identify its specific domain and ONLY load the corresponding rule file from [`.agents/rules/`](rules/). NEVER load all rule files at once.
- **No Unsolicited Commits/Pushes**: NEVER run `git commit`, `git push`, or alter repository git state unless explicitly requested by the user.

---

## Domain-Specific Architecture & Rule Modules

Project rules and architecture guidelines are organized into domain-specific modules in [`.agents/rules/`](rules/):

1. **[Clean Architecture & Platform API](rules/architecture.md)**:
   - Ponytail (YAGNI), Linus's Law (preserve userspace experience & visual integrity).
   - No Objective-C runtime reflection (KVC / selectors).
   - 3-tier API precedence (Public First $\rightarrow$ Public API + Private ID via Bridging Header $\rightarrow$ Strict Private API Ban).
   - CryptoKit & AppIconProvider caching (`NSCache`).
   - Swift concurrency over GCD, Combine filter debouncing, resource cleanup in `deinit`.

2. **[Endpoint Security & Low-Level Process Control](rules/endpoint-security.md)**:
   - `AUTH_EXEC` PID assignment timing (`pid = 0`, never call `kill(0, signal)`).
   - `NOTIFY_EXEC` pre-exec vs post-exec audit tokens (`pidversion` increment rule).
   - POSIX liveness & PID recycling defense.
   - Extension safety valve (watchdog) & graceful termination flush.

3. **[Unified Logging & Observability](rules/logging.md)**:
   - Apple Unified Logging (`os.Logger`) category hierarchy (`Logfile`).
   - Semantic log level decision matrix (`.debug`, `.info`, `.notice`, `.warning`, `.error`, `.fault`).
   - Structured privacy interpolation (`privacy: .public`). Zero `print()` / `NSLog()`.

4. **[Swift Concurrency & Thread Isolation](rules/concurrency.md)**:
   - Minimize `nonisolated(unsafe)`, prefer instance methods and dependency injection.
   - `@MainActor` enforcement for UI state models, XPCServer, and window controllers.
   - Background queue isolation for I/O & cryptography; structured task cancellation tracking.

5. **[Swift Quality, Linting & API Style](rules/swift-quality.md)**:
   - Zero deprecated API tolerance (macOS 14+); mandatory SwiftLint (0 errors, 0 warnings).
   - Function complexity ($\le 10$), body length ($\le 50$), parameters ($\le 5$), line length ($\le 120$).
   - Fluent English API phrasing, strongly typed errors, `[weak self]` in escaping closures/Tasks.

6. **[Liquid Glass & macOS UI Design](rules/ui-design.md)**:
   - HIG Materials architecture: Functional Layer (`glassEffect`) vs. Content Layer (`Material`).
   - Strict content layer glass ban (transient interaction exception only).
   - Liquid Glass variants: `regular` for text/sidebars; `clear` for media + 35% dimming layer.
   - Semantic system colors (zero hardcoded hex/RGB), WCAG 4.5:1 contrast, concentric curvature ($r_{\text{in}} = r_{\text{out}} - p$).
   - Mandatory icon `.accessibilityLabel`, destructive action confirmation safeguards.

7. **[macOS Window Architecture & Platform Integrity](rules/ui-window-architecture.md)**:
   - 100% transparent AppKit window skeleton & SwiftUI UI ownership (no opaque backgrounds, no CALayer hacks).
   - Traffic light insets (`~14pt` top, `54–68pt` leading), titlebar drag isolation (`WindowDragArea`).
   - Native `.searchable` toolbar integration; optical glass scattering vs. strict clipping scroll patterns.
   - Modern UI state management (`@Observable` macro over Combine/ObservableObject).

8. **[XPC Resilience & IPC Lifecycle](rules/xpc-and-security.md)**:
   - Explicit XPC protocol definitions without optional method overloads.
   - Auto-reconnect on invalidation, safe proxy error handling.
   - Persistent Security-Scoped Bookmarks & chunked streamed I/O.

9. **[Localization & Communication Guidelines](rules/localization.md)**:
   - English base localization keys with static String literals (clean Xcode string catalog extraction).
   - Primary communication in Vietnamese with standard technical terms in English.

10. **[Git Commit Style & Operational Safety Guidelines](rules/git-commits.md)**:
    - Absolute ban on unsolicited commits & pushes (`git commit`, `git push` only when requested).
    - Conventional commit types (`feat`, `fix`, `perf`, `chore`, `refactor`, `ci`, `docs`, `test`).
    - Subject for users (Sparkle changelog), body for developers.
