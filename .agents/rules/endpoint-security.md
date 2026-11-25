# Endpoint Security & POSIX Signal Gotchas (CRITICAL)

## 1. Execution Interception & Kernel PID Guard
- `ESAuthorizer` subscribes to `ES_EVENT_TYPE_NOTIFY_EXEC`, `ES_EVENT_TYPE_AUTH_SIGNAL`, and `ES_EVENT_TYPE_NOTIFY_EXIT` (not `AUTH_EXEC`, where `audit_token_to_pid` returns **PID = 0** before process instantiation completes).
- **DO NOT** invoke `kill(0, signal)`. In POSIX/macOS C, `kill(0, signal)` sends the signal to **the entire process group of the caller (`ESExtension`)**, which disrupts XPC connections (`NSCocoaErrorDomain Code=4097`).

## 2. Pre-Exec vs Post-Exec Audit Token (`NOTIFY_EXEC`)
- In `NOTIFY_EXEC` events (`es_event_exec_t`):
  - `message.process.audit_token` represents the **pre-exec** process state (before binary loading).
  - `message.event.exec.target.audit_token` represents the **post-exec** process state (after `execve()` has completed).
  - **`pidversion` Increment Rule**: Darwin XNU Kernel increments `pidversion` by 1 upon every successful `execve()`.
  - **MANDATORY**: Always extract PID and `audit_token_t` from **`message.event.exec.target.pointee.audit_token`** when registering pending processes. Using `message.process` will cause `pidversion` mismatch (`expected != current`) and falsely trigger PID recycling aborts.

## 3. POSIX Liveness & PID Recycling Guard
- **Liveness Check**: Always enforce `guard pid > 0, kill(pid, 0) == 0` before issuing any signal to safely skip dead or terminated processes.
- **PID Recycling Defense**: Compare `audit_token_to_pidversion` of the currently running process (via `task_info(TASK_AUDIT_TOKEN)` in `verifyProcessIdentity`) with the stored `audit_token_t` from `NOTIFY_EXEC` before invoking `kill(pid, SIGCONT)` or `kill(pid, SIGKILL)`.
- **Terminating Suspended Processes**: When rejecting or timing out a `SIGSTOP`-frozen process (`terminateFrozenProcess`), send `SIGKILL` followed by `SIGCONT` so XNU unfreezes the dispatch loop and terminates cleanly without hanging `launchd`.

---

## Fail-Safe & Recovery Rules (Fail-Closed)

- **75s Pending Process Watchdog (`ESManager+Watchdog.swift`)**:
  - `ESExtension` polls `pendingVerificationProcesses` every 15s and terminates (`SIGKILL` + `SIGCONT`) any process waiting longer than 75s without authentication, notifying the Main App via `notifyProcessExited(pid:)`.
- **Main App Disconnect & Guardian Watchdog (`ESEventNotifyExit.swift`)**:
  - If the Main App disconnects or exits unexpectedly (`exit.stat != 0`) while processes are pending, `ESExtension` **preserves** the Fail-Closed queue (never unfreezes blocked apps), refreshes `registeredAt` timestamps, and kickstarts `com.TranPhuong319.AppLocker.agent` via `AppLauncherUtils` (immediately on disconnect with pending apps, or after a 10s Guardian delay on crash). Upon reconnect, `reNotifyPendingVerificationProcesses` resends the pending list.
- **AUTH Event Deadline Safety Valve (`ESSafetyValve`)**:
  - `AUTH_*` events (`ESAuthorizer` `AUTH_SIGNAL`, `ESTamper` `AUTH_OPEN`/`UNLINK`/`RENAME`/etc. — `ESTamper` is active in Release only) race `authorizationProcessingQueue` against `emergencyTimerQueue` using `ESSafetyValve` and respond `ES_AUTH_RESULT_DENY` if the kernel deadline budget is reached.

---

## 4. Self-Defense, Bundle Paths & Daemon Verification
- **Audit Token Verification in File Auth**: `ESEventAuthFile.isAuthorized` must verify `isMainAppTarget` (`pidversion` + `CodeSignatureValidator`), never raw PID equality alone.
- **Per-UID Folder & Bundle Mutation Coverage**: `isPathAllowedForUID` blocks non-root writes/deletes on `/Users/Shared/AppLocker` root and unrecognized subpaths (restricting legacy `config.plist` cleanup to main app). Cover `AUTH_RENAME` destination dir/path as well as both source and target of `AUTH_CLONE` / `AUTH_LINK`, and dynamically allowlist valid `/Applications/.../AppLocker.app` install paths via `ESTamper.addAllowlistPath`.
- **Restarting `ESExtension` in Real Tests**: `AUTH_SIGNAL` blocks `kill` even under `sudo`; restart the daemon via `sudo launchctl kickstart -k system/endpoint-security.com.TranPhuong319.AppLocker.ESExtension`.
