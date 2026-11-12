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

- **Prefix & Tagging**: Always prefix messages with component identifier: `[Component] Action description - Details` (e.g. `Logfile.policy.debug("[ConfigStore] Saved \(count, privacy: .public) apps to disk")`).
- **Privacy Interpolation**: Mark diagnostic identifiers (PIDs, paths, counts, durations, status codes) as `privacy: .public` to avoid `<private>` redaction in Console.app.
- **Zero `print()` / `NSLog()`**: Absolutely never use `print()` or `NSLog()`. All logging must route through `Logfile`.

## 4. Concrete Code Examples

```swift
// Example 1: High-Frequency / Timing Debug Trace
Logfile.security.debug("[Keychain] Ephemeral EC keys generated in \(elapsedMs, format: .fixed(precision: 1))ms")

// Example 2: Normal Lifecycle State Transition Info
Logfile.app.info("[Bootstrap] AppLocker v\(Bundle.main.fullVersion, privacy: .public) starting...")

// Example 3: High-Value Security Notice
Logfile.appXPC.notice("[Auth] Batch authentication approved for \(approvedPIDs.count, privacy: .public) application(s)")

// Example 4: Recoverable Fallback / Anomaly Warning
Logfile.app.warning("[Installer] Move to /Applications failed via FileManager: \(error.localizedDescription), falling back to AppleScript")

// Example 5: Syscall / Operation Error
Logfile.endpointSecurity.error("[Process] Failed to send SIGKILL to PID \(pid, privacy: .public): errno \(errno, privacy: .public)")

// Example 6: Security Violation / System Tampering Fault
Logfile.esSecurity.fault("[Auth] CDHash mismatch between running process and disk binary for PID \(pid, privacy: .public)!")
```
