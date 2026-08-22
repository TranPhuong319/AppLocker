# Tasks: Modernize Application State Observation with @Observable

**Feature**: `001-migrate-observable-state`
**Date**: 2026-08-22
**Spec**: [spec.md](file:///Volumes/Xcode%20Project/AppLocker/specs/001-migrate-observable-state/spec.md) | **Plan**: [plan.md](file:///Volumes/Xcode%20Project/AppLocker/specs/001-migrate-observable-state/plan.md)

---

## Phase 1: Setup

**Purpose**: Verify base workspace environment and prerequisites

- [x] T001 Verify base workspace build status and SwiftLint baseline

---

## Phase 2: Foundational (Core Protocols & Service State Stores)

**Purpose**: Core model and protocol migrations that MUST be complete before view updates

**⚠️ CRITICAL**: Must complete before updating dependent UI views and coordinators

- [x] T002 [P] Remove `ObservableObject` inheritance from `LockManagerProtocol` in `AppLocker/Services/LockManagerProtocol.swift`
- [x] T003 [P] Migrate `LockES` to `@Observable` macro, remove `@Published`, and add update callback in `AppLocker/Services/LockES.swift`
- [x] T004 [P] Migrate `XPCServer` to `@Observable` macro and remove `@Published` and `ObservableObject` in `AppLocker/EndpointSecurity/XPCServer.swift`
- [x] T005 [P] Migrate `ExtensionInstaller` to `@Observable` macro and remove `@Published` and `ObservableObject` in `AppLocker/EndpointSecurity/ExtensionInstaller.swift`
- [x] T006 [P] Migrate `MockLockManager` to `@Observable` macro in `AppLocker/Services/AppState/AppState+Preview.swift`

**Checkpoint**: Foundation ready - all core service state stores migrated to `@Observable`.

---

## Phase 3: User Story 1 - Real-time Lock State Synchronization Across All Windows (Priority: P1) 🎯 MVP

**Goal**: Seamless, instant lock/unlock state synchronization across all application windows with zero lag.

**Independent Test**: Lock/unlock an app in Settings and verify immediate synchronization in Menu Bar popover and main window with no manual refresh.

### Implementation for User Story 1

- [x] T007 [US1] Migrate `AppState` class to `@Observable`, remove `@Published`, and remove Combine `cancellables` in `AppLocker/Services/AppState/AppState.swift`
- [x] T008 [US1] Update `ContentView` to use `@Bindable var appState` in `AppLocker/Appearance/View/MainUI/ContentView.swift`
- [x] T009 [P] [US1] Update `MainUIButtons` to consume `@Observable AppState` in `AppLocker/Appearance/View/MainUI/Button/MainUIButtons.swift`
- [x] T010 [P] [US1] Update `AddAppSheet` and `DeleteQueueSheet` to consume `@Observable AppState` in `AppLocker/Appearance/View/MainUI/Sheets/AddAppSheet.swift` and `AppLocker/Appearance/View/MainUI/Sheets/DeleteQueueSheet.swift`
- [x] T011 [P] [US1] Update `BatchAuthView` to consume `@Observable XPCServer` in `AppLocker/Appearance/View/BatchAuth/BatchAuthView.swift`
- [x] T012 [P] [US1] Migrate `TouchBarManager` button observations to `withObservationTracking` and eliminate `cancellables` in `AppLocker/Appearance/TouchBar/TouchBarManager.swift`

**Checkpoint**: User Story 1 functional - full multi-window reactive state synchronization working.

---

## Phase 4: User Story 2 - Smooth and Responsive UI During High-Frequency Background Events (Priority: P2)

**Goal**: Ensure fluid 60/120 fps animations and zero frame drops during heavy search filtering or daemon background signals.

**Independent Test**: Rapidly type in the search bar and verify smooth 200ms debounced filtering with prior task cancellation.

### Implementation for User Story 2

- [x] T013 [US2] Implement structured Swift Concurrency `Task` debounce (200ms) with automatic cancellation for search filters in `AppLocker/Services/AppState/AppState.swift`
- [x] T014 [US2] Adapt `AppState+Spotlight.swift` and `AppState+AppPicker.swift` to fine-grained `@Observable` properties and ensure `@MainActor` thread isolation

**Checkpoint**: User Stories 1 AND 2 functional - search debounce runs via Swift Concurrency tasks without Combine.

---

## Phase 5: User Story 3 - Instantaneous Settings Persistence & Preference Updates (Priority: P3)

**Goal**: Ensure preferences and security extension toggles update reactively throughout the UI.

**Independent Test**: Toggle security extension or auto-start settings and verify immediate UI adaptation.

### Implementation for User Story 3

- [x] T015 [US3] Update `SecuritySettingsTab` to consume `@Observable ExtensionInstaller` in `AppLocker/Appearance/View/Settings/SecuritySettingsTab.swift`

**Checkpoint**: All user stories functional.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Quality gates, SwiftLint compliance, and validation

- [x] T016 [P] Run `swiftlint lint` and ensure 0 violations across all modified files
- [x] T017 Run build verification and quickstart validation scenarios per `specs/001-migrate-observable-state/quickstart.md`

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies.
- **Foundational (Phase 2)**: Depends on Setup (Phase 1) - BLOCKS all UI stories.
- **User Story 1 (Phase 3)**: Depends on Phase 2.
- **User Story 2 (Phase 4)**: Depends on Phase 3 (`AppState` migration).
- **User Story 3 (Phase 5)**: Depends on Phase 2 (`ExtensionInstaller` migration).
- **Polish (Phase 6)**: Depends on all user stories being completed.

---

## Parallel Execution Opportunities

- T002, T003, T004, T005, T006 can run in parallel.
- T009, T010, T011, T012 can run in parallel once T007 is completed.
- T016 can run in parallel with documentation checks.
