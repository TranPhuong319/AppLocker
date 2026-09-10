# Endpoint Security & POSIX Signal Gotchas (CRITICAL)

## 1. Kernel PID Assignment Timing
- In `AUTH_EXEC` events, macOS Kernel has not completed process instantiation. `audit_token_to_pid` returns **PID = 0**.
- **DO NOT** invoke `kill(0, signal)`. In POSIX/macOS C, `kill(0, signal)` sends the signal to **the entire process group of the caller (`ESExtension`)**, which disrupts XPC connection (`NSCocoaErrorDomain Code=4097`).

## 2. Pre-Exec vs Post-Exec Audit Token (`NOTIFY_EXEC`)
- In `NOTIFY_EXEC` events (`es_event_exec_t`):
  - `message.process.audit_token` represents the **pre-exec** process state (before binary loading).
  - `message.event.exec.target.audit_token` represents the **post-exec** process state (after `execve()` has completed).
  - **`pidversion` Increment Rule**: Darwin XNU Kernel increments `pidversion` by 1 upon every successful `execve()`.
  - **MANDATORY**: Always extract PID and `audit_token_t` from **`message.event.exec.target.pointee.audit_token`** when registering pending processes. Using `message.process` will cause `pidversion` mismatch (`expected != current`) and falsely trigger PID recycling aborts.

## 3. POSIX Liveness & PID Recycling Guard
- **Liveness Check**: Always enforce `guard pid > 0, kill(pid, 0) == 0 else { continue }` before issuing any signal to safely skip dead or terminated processes.
- **PID Recycling Defense**: Compare `audit_token_to_pidversion` of the currently running process (via `task_info(TASK_AUDIT_TOKEN)`) with the stored `audit_token_t` from `NOTIFY_EXEC` before invoking `kill(pid, SIGCONT)` or `kill(pid, SIGKILL)` to prevent sending signals to a recycled process ID.

---

## Fail-Safe & Process Recovery Rules

- **Watchdog / Extension Safety Valve**:
  - ESExtension must maintain an internal timeout/watchdog for pending blocked processes. If the Main App crashes or does not respond within the safety window (e.g. 30–60s), unfreeze or safely handle pending processes to prevent permanent system freeze.
- **Graceful Termination & Pending Queue Flush**:
  - When Main App terminates (`applicationWillTerminate` or receiving termination signal), notify the Extension to flush pending queues and resume paused processes if appropriate.
