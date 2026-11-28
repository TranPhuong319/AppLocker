# Custom Agent Rules & Architecture Guidelines

## Operational Safety & Rule Governance

- **Rule Size Ceiling ($\le 12,000$ bytes)**: Every file in `.agents/rules/` and `AGENTS.md` is capped at 12,000 bytes (enforced by `file-guard`).
- **On-Demand Rule Loading**: Load ONLY the matching domain file from [`.agents/rules/`](rules/). Do NOT load all rule files at once.
- **Verification Pipeline (`Lint -> Build -> Test`)**: After Swift code changes, run in order (`swiftlint` is gated at `Stop` via `swiftlint-gate`):
  1. `swiftlint lint --strict` (0 warnings, 0 errors).
  2. Prefer Xcode MCP (`BuildProject`, `RunSomeTests`, `RunAllTests`, `XcodeRefreshCodeIssuesInFile`) for Debug incremental builds, unit tests, and diagnostics when an Xcode window is open (`XcodeListWindows`).
  3. Fall back to `xcodebuild` CLI when specific flags are needed:
     - Tests / TSan: `xcodebuild test -scheme AppLocker -destination 'platform=macOS' [-enableThreadSanitizer YES] -only-testing:AppLockerTests`
     - Release build: `xcodebuild build -scheme AppLocker -configuration Release -destination 'platform=macOS'` (in-project build scripts handle code signing; never override `CODE_SIGN_IDENTITY` or `CODE_SIGNING_REQUIRED`).
- **No Unsolicited Commits/Pushes**: Never run `git commit`, `git push`, or mutate git state unless explicitly asked (gated by `git-guard`).
- **Xcode Project File Operations**: When Xcode MCP (`xcode-tools`) is enabled, prefer `XcodeWrite`/`XcodeMV`/`XcodeRM` to add, move, or remove `.swift` files so `AppLocker.xcodeproj` target memberships stay in sync.
- **Editing `.xcscheme` While Xcode Is Open**: Xcode caches `.xcscheme` XML in memory and silently overwrites external disk edits when opening/closing Edit Scheme or saving the workspace. Quit Xcode first before editing `.xcscheme` externally, or instruct the user to update the script directly in Xcode's Edit Scheme UI.
- **Copy-Paste Terminal Snippets**: Omit `#` comment lines in shell commands meant to be pasted into macOS interactive `zsh` (default `INTERACTIVE_COMMENTS` is off).

---

## Domain Rule Routing

| Domain | File | Primary Scope |
|---|---|---|
| **Clean Architecture & APIs** | [`rules/architecture.md`](rules/architecture.md) | YAGNI, 3-tier API precedence, `Security` validation, `NSCache`, `Bridging-Header.h`. |
| **Endpoint Security & Kernel** | [`rules/endpoint-security.md`](rules/endpoint-security.md) | `NOTIFY_EXEC` post-exec target token, `SIGSTOP`/`AUTH_SIGNAL`, PID recycling defense, Fail-Closed watchdogs. |
| **Unified Logging** | [`rules/logging.md`](rules/logging.md) | `os.Logger` (`Logfile`), semantic levels (`.debug` to `.fault`), `privacy: .public` on IDs. |
| **Concurrency & Actors** | [`rules/concurrency.md`](rules/concurrency.md) | `@MainActor` UI/XPC lifecycle, background queues/Tasks for I/O & ES, Swift 6 safety. |
| **Swift Quality & Style** | [`rules/swift-quality.md`](rules/swift-quality.md) | SwiftLint compliance, fluent API naming, structured errors, `[weak self]` in closures. |
| **UI Design & Materials** | [`rules/ui-design.md`](rules/ui-design.md) | Liquid Glass vs Material, semantic colors, deliberate SF symbol transitions (`magicSymbolReplace`). |
| **macOS Window Architecture** | [`rules/ui-window-architecture.md`](rules/ui-window-architecture.md) | `WindowManager.createWindow`, opaque canvas + Window Server titlebar blur, fluid NavigationSplitView detail. |
| **XPC Resilience & IPC** | [`rules/xpc-and-security.md`](rules/xpc-and-security.md) | Explicit protocols (no optional overloads), `CodeSignatureValidator` auth, auto-reconnect. |
| **Localization & Language** | [`rules/localization.md`](rules/localization.md) | English base String catalog keys; user communication in Vietnamese with standard English technical terms. |
| **Git Commit Workflow** | [`rules/git-commits.md`](rules/git-commits.md) | Conventional Commits (`feat`, `fix`, `perf`, `chore`), Sparkle user-facing subjects, dev-facing bodies. |

