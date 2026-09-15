<!--
Thank you for your contribution to AppLocker!
Please ensure your PR title follows Conventional Commits:
  <type>(<scope>): <user-facing summary>
  e.g., feat(touchbar): add quick lock action to control strip
        fix(auth): prevent duplicate prompt on rapid app launches
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
- [ ] **Memory & Resource Safety**: Retain cycles prevented via `[weak self]` in escaping closures/Tasks; resources cleanly released in `deinit`.
- [ ] **Architecture Integrity**: Clean separation of concerns; zero Objective-C runtime reflection (KVC); 3-tier API precedence followed.
- [ ] **UI & Liquid Glass (if applicable)**: Complies with Liquid Glass materials, semantic system colors, WCAG 4.5:1 contrast, and accessibility labels.
- [ ] **Endpoint Security (if applicable)**: Safe PID handling (never `kill(0, signal)`), correct audit token handling, and graceful termination safety.

---

## 🧪 Testing & Verification

### Test Environment
- **macOS Version:** macOS 14.x / macOS 15.x
- **Hardware Architecture:** Apple Silicon / Intel
- **Device / Simulator:** Physical Mac

### Steps Performed
<!-- Describe the manual verification or automated test steps conducted -->
1. 
2. 

### Screenshots / Screen Recordings (if applicable)
<!-- Attach before/after screenshots or screen recordings for UI changes -->
