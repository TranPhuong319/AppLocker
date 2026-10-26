# Custom Agent Rules & Architecture Guidelines

## Operational Safety & Rule Governance

- **Rule Size Ceiling ($\le 12,000$ chars/bytes)**: Every rule file in `.agents/rules/` and `AGENTS.md` must stay strictly under 12,000 characters/bytes.
- **On-Demand Rule Loading**: Identify the active task's domain and load ONLY the corresponding rule file from [`.agents/rules/`](rules/). Do NOT load all rule files into context at once.
- **No Unsolicited Commits/Pushes**: NEVER run `git commit`, `git push`, or alter repository git state unless explicitly requested by the user.

---

## Domain Rule Routing

| Domain | File | Primary Scope |
|---|---|---|
| **Clean Architecture & APIs** | [`rules/architecture.md`](rules/architecture.md) | YAGNI, 3-tier API precedence, CryptoKit, NSCache, no Obj-C KVC/reflection. |
| **Endpoint Security & Kernel** | [`rules/endpoint-security.md`](rules/endpoint-security.md) | `AUTH_EXEC` PID=0 guard, `NOTIFY_EXEC` post-exec target token, PID recycling defense, watchdog. |
| **Unified Logging** | [`rules/logging.md`](rules/logging.md) | `os.Logger` (`Logfile`), semantic levels (`.debug` to `.fault`), `privacy: .public` on IDs, zero `print()`. |
| **Concurrency & Actors** | [`rules/concurrency.md`](rules/concurrency.md) | `@MainActor` UI/XPC lifecycle, background queues for heavy I/O, Swift 6 safety. |
| **Swift Quality & Style** | [`rules/swift-quality.md`](rules/swift-quality.md) | SwiftLint compliance, fluent API naming, strongly-typed errors, `[weak self]` in closures. |
| **UI Design & Materials** | [`rules/ui-design.md`](rules/ui-design.md) | Liquid Glass vs Material, semantic colors, deliberate SF symbol state transitions (`.replace.magic`). |
| **macOS Window Architecture** | [`rules/ui-window-architecture.md`](rules/ui-window-architecture.md) | `WindowManager.createWindow`, opaque canvas + Window Server titlebar blur, fluid NavigationSplitView detail. |
| **XPC Resilience & IPC** | [`rules/xpc-and-security.md`](rules/xpc-and-security.md) | Explicit protocols (no optional overloads), auto-reconnect, Security-Scoped Bookmarks. |
| **Localization & Language** | [`rules/localization.md`](rules/localization.md) | English base String catalog keys; user communication in Vietnamese with standard English technical terms. |
| **Git Commit Workflow** | [`rules/git-commits.md`](rules/git-commits.md) | Conventional Commits (`feat`, `fix`, `perf`, `chore`), Sparkle user-facing subjects, dev-facing bodies. |

