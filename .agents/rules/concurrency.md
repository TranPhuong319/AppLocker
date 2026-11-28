# Concurrency & Thread Isolation Rules

- **Thread Safety & Mutable State**:
  - Minimize `nonisolated(unsafe)`. Eliminate global mutable state; prefer dependency injection or actor-isolated state.
  - Pure `static` helpers (pure functions, zero mutable state) and bounded system singletons (`AppIconProvider.shared`, `Logfile`, `WindowManager`) are valid; avoid mutable global singletons (`sharedInstanceForCallbacks`).
- **Main Thread (`@MainActor`)**:
  - `XPCServer`, `AuthCoordinator`, `LockES`, `BatchAuthWindowController`, `AppState`, and all `@Observable` UI state models MUST be executed on `@MainActor`.
  - All UI state changes and window operations must originate from `@MainActor` methods.
- **Background Queues & Interop**:
  - CDHash/code-signature inspection, file I/O, `OSLogStore` queries (`LogReader` actor), and ES event processing MUST run on background queues, actors, or non-main Tasks.
  - NEVER perform blocking thread synchronization (`Thread.sleep`, `.wait()`) on `@MainActor`.
  - Background XPC/C callbacks bridging to the main thread should dispatch via `Task { @MainActor in ... }` or `DispatchQueue.main.async`; observers registered explicitly on `.main` queue may use `MainActor.assumeIsolated`.
- **Structured Task Cancellation**:
  - Hold references to long-running asynchronous tasks (`Task<Void, Never>?`) and explicitly cancel them (`task?.cancel()`) in `deinit` or during view/window teardown.
- **Testable Async DI Defaults (`SWIFT_APPROACHABLE_CONCURRENCY`)**:
  - On `@MainActor` types, prefer optional closure defaults (`((...) async throws -> T)? = nil`) over inline default-argument closures calling actor methods (`try await Actor.shared.method(...)`), avoiding `No 'async' operations occur within 'await' expression` under `SWIFT_TREAT_WARNINGS_AS_ERRORS = YES`.
