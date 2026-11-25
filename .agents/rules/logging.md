# Unified Logging & Observability Guidelines

## 1. Logger Taxonomy & Subsystem Architecture
AppLocker uses Apple's native Unified Logging (`os.Logger`) organized into a strict two-tier hierarchy: **Subsystem (Process Boundary) $\rightarrow$ Category (Functional Layer)**.

```swift
public enum Logfile {
    // MARK: - Main App Subsystem (com.TranPhuong319.AppLocker)
    public static let app = Logger(subsystem: "com.TranPhuong319.AppLocker", category: "App")
    public static let policy = Logger(subsystem: "com.TranPhuong319.AppLocker", category: "Policy")
    public static let appXPC = Logger(subsystem: "com.TranPhuong319.AppLocker", category: "XPC")
    public static let security = Logger(subsystem: "com.TranPhuong319.AppLocker", category: "Security")

    // MARK: - ESExtension Subsystem (com.TranPhuong319.AppLocker.ESExtension)
    public static let endpointSecurity = Logger(subsystem: "com.TranPhuong319.AppLocker.ESExtension", category: "EndpointSecurity")
    public static let esXPC = Logger(subsystem: "com.TranPhuong319.AppLocker.ESExtension", category: "XPC")
    public static let esSecurity = Logger(subsystem: "com.TranPhuong319.AppLocker.ESExtension", category: "Security")
}
```

## 2. Semantic Log Level Decision Matrix

| Log Level | Purpose & Retention | When to Use |
|---|---|---|
| **`.debug`** | Verbose / High-frequency trace. Not persisted to disk in Release builds unless live streamed. | Benchmark timings, loop steps, debounce ticks, raw payload dumps, allowlist matches, non-critical cache/IO status. |
| **`.info`** | Operational telemetry & state transitions. Persisted in memory / transient disk. | App/service startup milestones, config load counts, XPC connection established, updater checking. |
| **`.notice`** (or `.log`) | **High-value business & security decisions**. Standard level visible in Console.app by default. | App execution blocked, user batch auth approved/cancelled, protection toggled, ES clients active. |
| **`.warning`** | Recoverable anomalies, non-fatal errors, timeouts, fallback branches. | Timeout reached (auto cancel), AppleScript fallback for file move, unauthorized main app exit detected. |
| **`.error`** | Operation failures, unexpected exceptions, syscall errors. | File write failure, failed to send SIGKILL/SIGCONT, XPC proxy acquisition failed, extension install failed. |
| **`.fault`** | Invariant violations, active tampering, critical corruption. | Binary CDHash mismatch between runtime process and disk, safety valve hard deadline exceeded. |

## 3. Log Formatting Rules

- **Prefix & Tagging**: Prefix messages with component identifier: `[Component] Action description - Details` (e.g. `Logfile.policy.debug("[ConfigStore] Saved \(count, privacy: .public) apps to disk")`).
- **Privacy Interpolation**: Mark diagnostic identifiers (PIDs, paths, counts, durations, status codes) as `privacy: .public` to avoid `<private>` redaction in Console.app.
- **Unified Only**: Route all logging through `Logfile` (`print()` / `NSLog()` are banned via SwiftLint).
