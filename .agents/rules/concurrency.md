# Concurrency & Thread Isolation Rules

- **Thread Safety & Mutable State**:
  - Minimize `nonisolated(unsafe)`. Eliminate global mutable state; prefer dependency injection or actor-isolated state.
  - Pure `static` helpers (pure functions, zero mutable state) and bounded system singletons (`AppIconProvider.shared`, `Logfile`, `WindowManager`) are valid; avoid mutable global singletons (`sharedInstanceForCallbacks`).
- **Main Thread (`@MainActor`)**:
  - `XPCServer`, `BatchAuthWindowController`, `AppState`, and all `@Observable` UI state models MUST be executed on `@MainActor`.
  - All UI state changes and window operations must originate from `@MainActor` methods.
- **Background Queues & Interop**:
  - SHA256 computation, file I/O, `CryptoKit` signatures, and ES event processing MUST run on background queues or non-main Tasks.
  - NEVER perform blocking thread synchronization (`Thread.sleep`, `.wait()`) on `@MainActor`.
  - Background XPC/C callbacks bridging to the main thread should dispatch via `Task { @MainActor in ... }` or `DispatchQueue.main.async`.
- **Structured Task Cancellation**:
  - Hold references to long-running asynchronous tasks (`Task<Void, Never>?`) and explicitly cancel them (`task?.cancel()`) in `deinit` or during view/window teardown.
