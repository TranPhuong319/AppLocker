# Quickstart & Validation Guide: State Observation Modernization

**Feature**: `001-migrate-observable-state`
**Date**: 2026-08-22

## Prerequisites & Build Verification

Ensure the project compiles without warnings and all SwiftLint rules pass.

```bash
# 1. Run SwiftLint to verify zero violations
swiftlint lint

# 2. Build Debug target
xcodebuild -project AppLocker.xcodeproj -scheme AppLocker -configuration Debug build
```

## Validation Scenarios

### Scenario 1: Real-time UI Reactive Updates
1. Launch AppLocker.
2. Open Settings (`Cmd+,`).
3. Click "Add App" to open `AddAppSheet`.
4. Select one or more applications and click "Lock".
5. **Expected Outcome**:
   - The selected applications are added to the locked list immediately.
   - Both the main `ContentView` and Settings views show the updated locked list with zero delay or manual refresh.

### Scenario 2: Search Debounce & Filter Responsiveness
1. In `AddAppSheet` or `ContentView`, type rapidly in the search bar.
2. Observe filter updates.
3. **Expected Outcome**:
   - Filter results update cleanly after a 200ms pause.
   - No UI stutter, no dropped frames, and no multiple redundant filter executions.

### Scenario 3: Batch Authorization Prompt Reactivity
1. Trigger a blocked application (or run test mock authorization).
2. The `BatchAuthView` window appears with the pending application item.
3. Authenticate with Touch ID or passcode.
4. **Expected Outcome**:
   - The pending application is released immediately.
   - The countdown timer ticks down reactively and disappears upon approval.

### Scenario 4: TouchBar Dynamic Updates
1. On a TouchBar-equipped Mac (or TouchBar simulator via Xcode > Window > Show TouchBar).
2. Select applications to delete/unlock.
3. **Expected Outcome**:
   - The TouchBar "Waiting to unlock N application(s)..." and "Lock" buttons update their titles and enabled/disabled states immediately via `withObservationTracking`.
