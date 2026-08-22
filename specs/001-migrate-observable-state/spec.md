# Feature Specification: Modernize Application State Observation

**Feature Branch**: `001-migrate-observable-state`

**Created**: 2026-08-22

**Status**: Draft

**Input**: User description: "Thay đổi: Sử dụng @Observable thay vì @Published,.."

## Clarifications

### Session 2026-08-22

- Q: Phạm vi chuyển đổi sang @Observable và cách xử lý search debounce? → A: Option C - Chuyển đổi toàn diện AppState, LockES, XPCServer và các ViewModel sang `@Observable`, loại bỏ hoàn toàn Combine/`@Published` và `cancellables`, chuyển sang dùng Swift Concurrency Tasks để xử lý debounce tìm kiếm.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Real-time Lock State Synchronization Across All Windows (Priority: P1)

As a user interacting with multiple AppLocker windows (Main Settings, Menu Bar Popover, Quick Search, and Batch Auth Prompts), I want state updates (such as locking or unlocking an app, toggling global protection, or modifying preferences) to reflect instantly and granularly across all open interfaces without UI lag or unnecessary screen redraws.

**Why this priority**: Core application functionality depends on accurate and instant visual feedback when security state or application configurations change. Granular state observation prevents UI hitching and ensures immediate user feedback.

**Independent Test**: Can be tested by locking/unlocking an application in Settings while the Menu Bar popover or Search sheet is open, verifying that state changes reflect immediately across all surfaces with zero delay.

**Acceptance Scenarios**:

1. **Given** the user is viewing the locked apps list in Settings, **When** they add a new application to the locked list, **Then** the application is instantly shown as locked across the UI without requiring a manual window refresh or re-opening.
2. **Given** an application is temporarily authorized via password/biometrics, **When** its grace period expires or it is manually locked again, **Then** all active UI views update its lock status indicator synchronously.

---

### User Story 2 - Smooth and Responsive UI During High-Frequency Background Events (Priority: P2)

As a user running heavy workloads and multiple applications, I want AppLocker's UI to remain smooth, lightweight, and responsive even when system daemon events and authorization checks occur frequently in the background.

**Why this priority**: Fine-grained property observation ensures only UI components directly depending on changed properties are re-rendered, reducing CPU usage, memory churn, and UI thread stutter.

**Independent Test**: Can be tested by executing multiple intercepted apps simultaneously while browsing Settings or scrolling app lists, confirming smooth 60/120 fps animations and instantaneous interaction response.

**Acceptance Scenarios**:

1. **Given** the user is scrolling the application list or typing in search filters, **When** background authorization checks or tamper events are reported by the daemon, **Then** user interactions remain smooth without frame drops or UI freezing.
2. **Given** a specific single property changes in global application state (such as update check status), **When** views that do not observe this property are on screen, **Then** unrelated view hierarchies are not unnecessarily refreshed.

---

### User Story 3 - Instantaneous Settings Persistence & Preference Updates (Priority: P3)

As a user customizing preferences (such as auto-start, menu bar visibility, or grace period durations), I want my preference updates to take effect immediately throughout the application without needing an app restart.

**Why this priority**: Users expect seamless live configuration updates where modifying a toggle or slider immediately reflects in both the UI and runtime enforcement behavior.

**Independent Test**: Can be tested by toggling preferences in Preferences and verifying that UI states and active behavior adapt immediately.

**Acceptance Scenarios**:

1. **Given** the user toggles a configuration setting in Preferences, **When** the value is updated, **Then** dependent UI components update instantly to reflect the new state.

---

### Edge Cases

- **Rapid Search Text Updates**: Rapid typing in search fields must cancel in-flight debounce tasks gracefully without thread race conditions or stale filter results.
- **Rapid Multi-Property Mutation**: What happens when multiple state properties update concurrently from different background signals? The system must ensure state consistency and avoid race conditions.
- **Deeply Nested State Changes**: How does the system handle updates to individual items inside collections (e.g. modifying the lock status of one specific app among hundreds)? Only the specific row/element must update.
- **Nil/Optional State Transitions**: How does the interface react when transient state properties (such as active prompt contexts or error messages) transition between populated and nil states? Transitions must animate cleanly without crashing or ghosting.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST provide unified, fine-grained reactive state tracking for all core application models (`AppState`, `LockES`, `XPCServer`, `ExtensionInstaller`) and view state stores using modern Swift Observation (`@Observable`).
- **FR-002**: System MUST eliminate legacy `ObservableObject`, `@Published`, and `Set<AnyCancellable>` memory management across all migrated state stores.
- **FR-003**: System MUST handle search query debouncing using structured Swift Concurrency (`Task` / `Task.sleep`) on the main actor, cancelling prior in-flight search tasks upon new input.
- **FR-004**: System MUST isolate UI re-evaluations so that changing a specific property only triggers re-renders on views actively reading that exact property.
- **FR-005**: System MUST guarantee thread safety and `@MainActor` confinement for all state modifications bound to UI presentations.
- **FR-006**: System MUST maintain seamless two-way data bindings between user controls (toggles, text fields, pickers) and backing `@Observable` state models.
- **FR-007**: System MUST preserve all existing security configurations, locked application rules, and user preferences across state migrations without data loss.

### Key Entities

- **Application State Store (`AppState`)**: The primary centralized `@Observable` state container managing locked application rules, active authorization sessions, tamper states, and user preferences.
- **Lock Management Service (`LockES`)**: The `@Observable` service mediating between the UI layer and the privileged Endpoint Security daemon.
- **Server Communication Coordinator (`XPCServer`)**: The `@Observable` coordinator managing active authentication prompts and pending application queues.
- **View Configuration Models**: Granular presentation state models backing individual window controllers, sheets, dialogs, and navigation flows.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% removal of `@Published` property wrappers and `ObservableObject` conformances from primary state stores (`AppState`, `LockES`, `XPCServer`, `ExtensionInstaller`).
- **SC-002**: Zero unnecessary view redraws when unrelated properties in the central state store change during normal operation.
- **SC-003**: Search debouncing executes accurately with a responsive 200ms window using native Swift Concurrency tasks with zero memory leaks.
- **SC-004**: State changes update and reflect in the UI within less than 16 milliseconds (maintaining a fluid 60+ fps experience).
- **SC-005**: 100% of existing functional capabilities (locking, unlocking, searching, preference modification, batch authorization) work with full feature parity.
- **SC-006**: 0% regression in user configuration persistence or data integrity during state modernization.

## Assumptions

- Target operating environment is macOS 14.0+ where the Swift Observation framework (`@Observable`) is natively supported.
- The user-facing behavior, visual design, and security enforcement mechanisms remain intact and functionally identical.
- All existing background daemon communications and XPC security guarantees continue to operate with full mutual authentication.
