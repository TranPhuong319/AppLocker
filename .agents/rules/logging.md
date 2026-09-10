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

## 3. Step-by-Step Recipe: How to Write Logs for Any Code/Feature

Whenever adding logging to any function, handler, or component, strictly follow these 5 steps:

1. **Step 1: Choose the Matching Logger Domain**:
   - UI / App Lifecycle / Updater $\rightarrow$ `Logfile.app`
   - Policy / Config Store / Rules $\rightarrow$ `Logfile.policy`
   - Main App IPC / XPC Server & Client $\rightarrow$ `Logfile.appXPC`
   - Main App Keychain & Touch ID $\rightarrow$ `Logfile.security`
   - Endpoint Security Interception / Watchdog $\rightarrow$ `Logfile.endpointSecurity`
   - ESExtension IPC / Mach Listener $\rightarrow$ `Logfile.esXPC`
   - ESExtension Signature / Caller Validation $\rightarrow$ `Logfile.esSecurity`

2. **Step 2: Select the Exact Semantic Level**:
   - Never default to `.log(...)` blindly. Use `.debug` for internal logic, `.info` for transitions, `.notice` for security actions, `.warning` for fallbacks, `.error` for failures, `.fault` for tampering.

3. **Step 3: Structure the Message with a Tag/Prefix**:
   - Format: `[Component/Tag] Action description - Details`
   - Example: `Logfile.policy.debug("[ConfigStore] Saved \(count, privacy: .public) apps to disk")`

4. **Step 4: Explicit Privacy Interpolation for Diagnostic IDs**:
   - Mark non-sensitive system identifiers as `privacy: .public` (e.g., PIDs, paths, counts, durations, status codes) so they are readable in Console.app and `log stream` without being redacted into `<private>`.

5. **Step 5: Zero `print()` / `NSLog()` Tolerance**:
   - Absolutely NEVER use `print()` or `NSLog()`. All logging MUST go through `Logfile`.

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
