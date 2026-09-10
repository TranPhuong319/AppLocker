# Swift Quality & Style Rules

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

## Error Handling & Silent Failure Ban

- **Zero Unlogged `try?` on Critical Paths**:
  - Never use `try?` on authentication, I/O, Keychain, CDHash extraction, or XPC serialization without a clear fallback and logging.
  - When `try?` is used for non-critical fallback branches, always log the result or reason at `.debug` or `.warning` level.
- **Strongly Typed App Errors**:
  - Use strongly typed error enums conforming to `LocalizedError` / `CustomNSError` for structured domain errors rather than generic String errors.

---

## Memory Management & Retain Cycles

- **Escaping Closures & Retain Cycles**:
  - Always use `[weak self]` in escaping closures, long-running asynchronous `Task` blocks, and notification observers referencing `NSWindowController`, `NSViewController`, or `AppState`.
