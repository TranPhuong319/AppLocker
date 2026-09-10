# XPC Protocol, Resilience & System Security

## XPC Protocol Design Rules

- **No Optional Method Overloading**: Avoid creating optional `@objc` method overloads with different parameter counts in `NSXPCInterface` protocols (e.g. `notifyBlockedExec(name:path:sha:)` vs `notifyBlockedExec(name:path:sha:pid:)`). Objective-C selector resolution may dispatch to the wrong fallback method and drop parameters.
- Keep XPC protocol definitions explicit, strict, and unambiguous.

---

## XPC Resilience & IPC Lifecycle Rules

- **Connection Invalidation & Auto-Reconnect**:
  - Never retain or reuse an `NSXPCConnection` once invalidated. Reset internal connection variables to `nil` in `invalidationHandler` so the next call lazily reinstantiates a healthy connection.
  - Clear `interruptionHandler` and `invalidationHandler` before calling `.invalidate()` to avoid recursive or dangling invalidation events.
- **Safe Proxy Invocations**:
  - Always invoke remote proxies via `remoteObjectProxyWithErrorHandler:` or `synchronousRemoteObjectProxyWithErrorHandler:` to catch communication failures and timeouts proactively instead of failing silently.

---

## Security-Scoped Bookmarks & File Access Integrity

- **Persistent User-Selected Paths**:
  - Use Security-Scoped Bookmarks (`bookmarkData(options:includingResourceValuesForKeys:relativeTo:)`) when storing custom user-selected binary or application paths across application relaunches.
- **Safe Streamed I/O**:
  - For large file inspection and hashing, stream chunks through `FileHandle` / memory mapping rather than reading multi-gigabyte binary files into RAM at once.
