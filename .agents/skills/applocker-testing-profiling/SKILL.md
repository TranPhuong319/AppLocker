---
name: applocker-testing-profiling
description: >-
  Runbook for testing and profiling AppLocker and ESExtension using Xcode Sanitizers,
  Instruments (xctrace), CLI heap tools (leaks/vmmap), and Unified Logging. Use when
  running TSan/ASan/UBSan test passes, profiling AppLocker with Instruments, inspecting
  ESExtension logs, or writing XPC/async unit tests.
---

# AppLocker Testing & Profiling Runbook

## 1. Multi-Pass Unit & Sanitizer Testing

Run `swiftlint lint --strict`, verify the `AppLocker` target builds (`BuildProject` or `xcodebuild build`), then run `AppLockerTests` across three isolated passes:

1. **Baseline + Coverage**:
   `xcodebuild test -scheme AppLocker -destination 'platform=macOS' -only-testing:AppLockerTests -resultBundlePath /tmp/applocker_baseline.xcresult`
   Inspect with `xcrun xccov view --report --only-targets /tmp/applocker_baseline.xcresult`.
2. **Thread Sanitizer (TSan)**:
   `xcodebuild test -scheme AppLocker -destination 'platform=macOS' -enableThreadSanitizer YES -only-testing:AppLockerTests`
3. **ASan + UBSan** (never combine with TSan):
   `xcodebuild test -scheme AppLocker -destination 'platform=macOS' -enableAddressSanitizer YES -enableUndefinedBehaviorSanitizer YES -only-testing:AppLockerTests`

## 2. Instruments (`xctrace`) & Live Memory / Log Tools

- **Post-Action vs. `ESTamper` Trap**: `AppLocker.xcscheme` `PostActions` runs `rm -rf /Applications/AppLocker.app` and `ditto`. When a Release `ESExtension` is `[activated enabled]`, `ESTamper` denies both (`SELF_PROT DENY` + `SecCodeCheckValidity status=-67050`) and blocks updating `/Applications/AppLocker.app`.
  - On Debug `ESExtension` builds, `AppLocker.xcscheme` `PostActions` temporarily bypasses and restores protection around `killall`/`rm -rf`/`ditto` via:
    `notifyutil -p com.TranPhuong319.AppLocker.ESExtension.debug.tamper.bypass` and `...restore` (with a `sleep 0.1` delivery margin and `trap ... EXIT`). On Release `ESExtension`, no bypass flag exists.
- **Profiling Running `AppLocker`**:
  - Live `--attach` works for `Time Profiler` and `Swift Concurrency` when `/Applications/AppLocker.app` is a Debug build (`com.apple.security.get-task-allow`), e.g.:
    `xcrun xctrace record --template "Time Profiler" --attach AppLocker --time-limit 10s --output /tmp/tp.trace`
  - `Allocations`/`Leaks` templates via `--attach` do not record heap tables without launch DYLD interposition; check live heap directly with `/usr/bin/leaks AppLocker` and `/usr/bin/vmmap -summary AppLocker`.
- **Unified Logging in `zsh`**: Always invoke `/usr/bin/log` (avoid shell builtin `log`):
  `/usr/bin/log show --predicate 'subsystem BEGINSWITH "com.TranPhuong319.AppLocker"' --last 30m --style compact`
- **`ESExtension` Constraints**: Both `ESTamper` and `evaluateSelfDefenseSignal` run in Debug and Release; in Debug, toggle bypass via `notifyutil -p com.TranPhuong319.AppLocker.ESExtension.debug.tamper.bypass` / `...restore`. Never ship `ESExtension.xcscheme` (`TSan` + `NSZombieEnabled`) for real workloads—kernel `AUTH_*` delays trip `ESSafetyValve` deadlines.
- **Debugging Under Xcode with `KeepAlive` LaunchAgent / Guardian**: When `com.TranPhuong319.AppLocker.agent` (`KeepAlive.SuccessfulExit = false`) is registered, quit `AppLocker` cleanly (`Cmd+Q` / Menu Bar Quit -> `exitStat == 0`) before `Cmd+R` and when finishing debug instead of `Cmd+.` Stop or `killall`. Abnormal exit (`stat != 0`) triggers a ~10s `launchd` respawn / `ESExtension` Guardian kickstart with `LAUNCHED_BY_LAUNCHD=1`, whose `enforceSingleInstance()` terminates the active Xcode LLDB session.

## 3. Unit Test Authoring Guardrails

- **Unresumed `ESXPCClient` Connections**: `connectionFactory` passed to `ESXPCClientConfiguration` MUST return an unresumed `NSXPCConnection` (`ESXPCClient.attemptConnect()` calls `conn.resume()`; resuming twice crashes `xctest`).
- **Deterministic Async Assertions**: Under `TSan`/`ASan+UBSan`, poll for concrete post-operation state (e.g., expected item content) instead of `Task.yield()` or `!store.isLoading` after unstructured `Task` launches like `reload()`.
