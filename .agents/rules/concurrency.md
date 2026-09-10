# Concurrency & Thread Isolation Rules

- **Minimize `nonisolated(unsafe)` & Prefer Instance Methods**:
  - Minimize the usage of `nonisolated(unsafe)` as much as possible. Only use it as a last resort when no safer concurrency solution exists without disrupting existing features or code stability.
  - Strongly prefer **Instance Methods (`self`)** and Dependency Injection over `static` methods and global singleton references (e.g. `sharedInstanceForCallbacks`). This ensures clean actor/thread ownership, eliminates global mutable state, and guarantees full Swift 6 Strict Concurrency safety.
- **Main Thread (`@MainActor`)**:
  - `XPCServer`, `BatchAuthWindowController`, `AppState`, and all `@Observable` UI state models MUST be executed on `@MainActor`.
  - All UI state changes and window operations must originate from `@MainActor` methods.
- **Background Queues**:
  - SHA256 computation, file I/O, `CryptoKit` signatures, and ES event processing MUST run on background queues (`authorizationProcessingQueue`, `xpcQueue`).
  - NEVER perform blocking thread synchronization (`Thread.sleep`, `.wait()`) on `@MainActor`.
  - XPC callbacks received on background queues must dispatch to `@MainActor` via `DispatchQueue.main.async`.
- **Structured Task Cancellation**:
  - Hold references to long-running asynchronous tasks (`Task<Void, Never>?`) and explicitly cancel them (`task?.cancel()`) in `deinit` or during view/window teardown.
