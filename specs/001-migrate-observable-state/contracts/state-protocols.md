# State Contracts & Interface Protocols

**Feature**: `001-migrate-observable-state`
**Date**: 2026-08-22

## Protocol Contracts

### 1. `LockManagerProtocol`
```swift
@MainActor
protocol LockManagerProtocol: AnyObject {
    var lockedApps: [String: LockedAppConfig] { get set }
    var allApps: [InstalledApp] { get set }
    var isProtectionDisabled: Bool { get }

    func toggleLock(for paths: [String])
    func setProtectionDisabled(_ disabled: Bool)
    func isLocked(path: String) -> Bool
}
```
*Note: `ObservableObject` conformance is removed.*

### 2. View Binding Interfaces
Views consuming `@Observable` state models bind directly:
- Read-only property access: `appState.lockedAppObjects`
- Two-way binding access: `@Bindable var appState: AppState` with `$appState.searchTextLockApps`
