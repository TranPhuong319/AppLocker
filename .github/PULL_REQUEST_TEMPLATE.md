<!--
Thank you for your contribution to AppLocker!
Please ensure your PR title follows Conventional Commits:
  <type>(<scope>): <user-facing summary>
  e.g., feat(menubar): add quick lock toggle to status item menu
        fix(ui): smooth SF Symbol transition with magic replacement
        fix(es): prevent race condition during PID recycling
        perf(cache): optimize app icon lookup with NSCache

Note:
  - Subject line is user-facing and will be used directly in Sparkle changelogs.
  - Using the scope '(ui)' (e.g. fix(ui): ...) automatically categorizes the item under 'UI Bug Fixes' in release notes.
-->

## 📋 Summary of Changes

<!--
Provide a clear, high-level summary of what this PR does.
Remember: The PR title and summary may be used for Sparkle changelogs.
-->

### Motivation & Context
<!-- Why is this change required? What problem does it solve? If it fixes an open issue, link it here (e.g. Fixes #123). -->

---

## 🏷️ Type of Change

<!-- Please mark the relevant option with an 'x' -->
- [ ] `feat`: A new user-facing feature
- [ ] `fix`: A user-facing bug fix
- [ ] `perf`: A performance or memory improvement
- [ ] `refactor`: Code restructuring with no behavior change
- [ ] `docs`: Documentation updates only
- [ ] `test`: Adding or updating test cases
- [ ] `chore`: Build scripts, dependencies, or CI changes

---

## 🛡️ Architecture & Code Quality Checklist

<!-- Please verify the following items before submitting your PR -->
- [ ] **SwiftLint**: Passes with 0 errors and 0 warnings (`swiftlint --strict`).
- [ ] **Platform Compatibility**: Targets macOS 14.0+ with zero deprecated API usage.
- [ ] **Swift Concurrency**: UI state, window controllers, and XPC endpoints are strictly `@MainActor` isolated; no unsafe concurrency.
- [ ] **Unified Logging (`os.Logger`)**: Zero `print()` / `NSLog()`; all logging routed through `Logfile` taxonomy with `privacy: .public` on diagnostic IDs.
- [ ] **Localization & String Catalog**: All user-facing strings localized in `Localizable.xcstrings`; zero hardcoded UI strings; passes `check_localization.py`.
- [ ] **Memory & Resource Safety**: Retain cycles prevented via `[weak self]` in escaping closures/Tasks; resources cleanly released in `deinit`.
- [ ] **Architecture Integrity**: Clean separation of concerns; zero Objective-C runtime reflection (KVC); 3-tier API precedence followed.
- [ ] **UI & Apple Delight (if applicable)**: Complies with Liquid Glass materials, semantic system colors, concentric curvature ($r_{\text{in}} = r_{\text{out}} - p$), accessibility labels, and Magic Replacement on SF Symbols (`.replace.magic(...)`).
- [ ] **Endpoint Security (if applicable)**: Safe PID handling (never `kill(0, signal)`), correct audit token handling, POSIX liveness safeguards, and graceful termination safety.
- [ ] **Code Health**: File length $\le 300$ lines (decomposed if $\ge 300$), function length $\le 50$ lines, cyclomatic complexity $\le 10$.

---

## 🧪 Testing & Verification

> [!NOTE]
> **Endpoint Security Testing Notice:**
> The Endpoint Security Extension (`ESExtension`) cannot execute inside the Xcode Simulator. All interception and security features must be verified on a physical Mac or macOS Virtual Machine with System Extensions enabled.

### Test Environment
- **macOS Version:** macOS 14.x / macOS 15.x / macOS 26.x / macOS 27.x
- **Hardware Architecture:** Apple Silicon / Intel
- **Device / Environment:** Physical Mac / macOS VM (Virtualization.framework)

### Steps Performed
<!-- Describe the manual verification or automated test steps conducted -->
1. 
2. 

### Screenshots / Screen Recordings (if applicable)
<!-- Attach before/after screenshots or screen recordings for UI changes -->
