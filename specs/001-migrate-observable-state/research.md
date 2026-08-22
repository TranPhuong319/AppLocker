# Research: Modernize State Observation with @Observable

**Feature**: `001-migrate-observable-state`
**Date**: 2026-08-22

## Research Findings & Architectural Decisions

### 1. State Store Architecture: Observation Framework (`@Observable`) vs Combine/`ObservableObject`

- **Decision**: Migrate `AppState`, `LockES`, `XPCServer`, `ExtensionInstaller`, and `MockLockManager` from `ObservableObject` with `@Published` to `@Observable` macro (Swift Observation framework, macOS 14+).
- **Rationale**:
  - Fine-grained property tracking: SwiftUI only redraws view bodies that read the modified properties, eliminating unnecessary parent view hierarchy invalidations.
  - Simplification: Removes `@Published` annotations, property wrappers, and boilerplate.
  - Seamless `@MainActor` thread safety.
  - Native platform first (Principle I & IV of Constitution).
- **Alternatives considered**:
  - *Keep `ObservableObject`*: Retains legacy Combine overhead, unnecessary view refreshes, and verbose `$property` bindings.
  - *Hybrid approach (Partial `@Observable`)*: Creates mental overhead and awkward bridging layers between Combine and Observation.

### 2. Search Query Debounce: Swift Concurrency (`Task.sleep`) vs Combine Publisher Pipeline

- **Decision**: Replace `Publishers.CombineLatest` and `.debounce(for:scheduler:)` in `AppState` with structured Swift Concurrency `Task` execution and `Task.sleep(for: .milliseconds(200))`.
- **Rationale**:
  - `@Observable` does not synthesize `$property` publishers by default. Creating artificial `PassthroughSubject` instances creates unnecessary complexity.
  - Swift Concurrency `Task` cancellation (`searchTask?.cancel()`) is instantaneous, clean, and runs natively on `@MainActor`.
  - Completely eliminates `Set<AnyCancellable>` from `AppState`.
- **Alternatives considered**:
  - *Combine Subjects (`PassthroughSubject`)*: Re-introduces Combine complexity and `cancellables` lifecycle management inside an otherwise pure `@Observable` class.
  - *Instant filtering on every keystroke (No debounce)*: Unnecessary CPU spikes when filtering large application lists during rapid typing.

### 3. AppKit Observation: `withObservationTracking` vs Notifications/Combine

- **Decision**: Use `withObservationTracking` for AppKit components (`TouchBarManager`, `LockTouchBarButton`, `DeleteQueueTouchBarButton`) that need to react to `@Observable` model mutations.
- **Rationale**:
  - `withObservationTracking` is Apple's official, native bridge for observing `@Observable` models outside of SwiftUI view bodies.
  - Automatically registers dependencies and triggers `onChange` callbacks when observed properties mutate.
  - Eliminates remaining `cancellables` in `TouchBarManager`.
- **Alternatives considered**:
  - *NotificationCenter broadcasting*: Introduces string-based/custom notification decoupling and manual post logic across models.
  - *Combine `objectWillChange`*: Incompatible with `@Observable` without custom bridging.

### 4. SwiftUI View Integration: `@Bindable` & Direct Property Access

- **Decision**:
  - Replace `@ObservedObject var appState: AppState` with `var appState: AppState` (or `@Bindable var appState: AppState` when two-way bindings like `$appState.searchTextLockApps` are required).
  - Replace `@StateObject` in `BatchAuthView` with standard `@State`.
  - Access shared singletons directly (e.g. `private var installer = ExtensionInstaller.shared`).
- **Rationale**:
  - Follows official Swift Observation guidelines for SwiftUI view hierarchies.
  - Cleaner syntax, zero property wrapper clutter.
