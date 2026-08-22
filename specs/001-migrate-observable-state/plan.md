# Implementation Plan: Modernize Application State Observation with @Observable

**Branch**: `001-migrate-observable-state` | **Date**: 2026-08-22 | **Spec**: [spec.md](file:///Volumes/Xcode%20Project/AppLocker/specs/001-migrate-observable-state/spec.md)

**Input**: Feature specification from `/specs/001-migrate-observable-state/spec.md`

## Summary

Migrate the application's reactive state architecture from legacy `ObservableObject`, `@Published`, and Combine pipelines to Apple's modern Swift Observation framework (`@Observable`) and Swift Concurrency Tasks on macOS 14.0+. This eliminates unnecessary view invalidations, cleans up boilerplate, replaces Combine search debounce pipelines with structured Task cancellation, and eliminates `Set<AnyCancellable>` memory management across the entire codebase.

## Technical Context

**Language/Version**: Swift 5.9+ / Swift 6 language mode compatible
**Primary Dependencies**: Native Apple Frameworks (Observation, SwiftUI, AppKit, Swift Standard Library)
**Storage**: Unchanged (`ConfigStore` JSON persistence on disk)
**Testing**: Unit tests, SwiftLint (`swiftlint lint`), manual interactive verification
**Target Platform**: macOS 14.0+
**Project Type**: Native macOS Application (`AppLocker`)
**Performance Goals**: 60/120 fps fluid UI rendering, <16ms state propagation latency, zero memory leaks from cancellables
**Constraints**: Zero regression in background daemon XPC security handshake and configuration persistence

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- [x] **Principle I (Native Platform First & YAGNI)**: Uses native `Observation` framework (`@Observable`, `@Bindable`, `withObservationTracking`) without third-party libraries.
- [x] **Principle II (Strict Process Interception & POSIX Safety)**: Preserves all ES process interception and signal safety guarantees unchanged.
- [x] **Principle III (Mutual Cryptographic Handshake & Defense in Depth)**: IPC and cryptographic authentication contracts remain fully intact.
- [x] **Principle IV (Thread Isolation & Swift Concurrency)**: All state classes (`AppState`, `LockES`, `XPCServer`, `ExtensionInstaller`) are strictly `@MainActor` isolated. Background tasks handle search debounce.
- [x] **Principle V (Clean Architecture & UI/Daemon Separation)**: Clear boundary between UI State (`AppLocker`) and Daemon (`ESExtension`).
- [x] **Principle VI (macOS Liquid Glass & HIG)**: Preserves all native UI styling and window behaviors.
- [x] **Principle VII (Zero-Tolerance Quality & Resource Integrity)**: `swiftlint lint` must pass with 0 errors and 0 warnings. Observers and tasks explicitly cancelled on teardown.

## Project Structure

### Documentation (this feature)

```text
specs/001-migrate-observable-state/
├── spec.md              # Feature specification
├── plan.md              # This file (/speckit-plan command output)
├── research.md          # Phase 0 output (/speckit-plan command)
├── data-model.md        # Phase 1 output (/speckit-plan command)
├── quickstart.md        # Phase 1 output (/speckit-plan command)
├── contracts/           # Phase 1 output (/speckit-plan command)
│   └── state-protocols.md
├── checklists/
│   └── requirements.md
└── tasks.md             # Phase 2 output (/speckit-tasks command)
```

### Source Code Impact

```text
AppLocker/
├── Services/
│   ├── AppState/
│   │   ├── AppState.swift             # [MODIFY] @Observable, remove @Published/Combine, Task search debounce
│   │   ├── AppState+Preview.swift     # [MODIFY] @Observable MockLockManager
│   │   ├── AppState+Spotlight.swift   # [MODIFY] Adapt to @Observable
│   │   └── AppState+AppPicker.swift   # [MODIFY] Adapt to @Observable
│   ├── LockES.swift                   # [MODIFY] @Observable, remove @Published
│   └── LockManagerProtocol.swift      # [MODIFY] Remove ObservableObject inheritance
├── EndpointSecurity/
│   ├── XPCServer.swift                # [MODIFY] @Observable, remove @Published/ObservableObject
│   └── ExtensionInstaller.swift       # [MODIFY] @Observable, remove @Published/ObservableObject
├── Appearance/
│   ├── View/
│   │   ├── MainUI/
│   │   │   ├── ContentView.swift      # [MODIFY] @Bindable var appState
│   │   │   ├── Button/MainUIButtons.swift # [MODIFY] var appState: AppState
│   │   │   └── Sheets/
│   │   │       ├── AddAppSheet.swift  # [MODIFY] @Bindable var appState
│   │   │       └── DeleteQueueSheet.swift # [MODIFY] var appState
│   │   ├── Settings/
│   │   │   └── SecuritySettingsTab.swift # [MODIFY] Adapt to ExtensionInstaller @Observable
│   │   └── BatchAuth/
│   │       └── BatchAuthView.swift    # [MODIFY] @State / @Bindable for XPCServer
│   └── TouchBar/
│       └── TouchBarManager.swift      # [MODIFY] Replace Combine with withObservationTracking
```

## Complexity Tracking

| Violation | Why Needed | Simpler Alternative Rejected Because |
|---|---|---|
| *None* | N/A | Fully adheres to standard native Observation and Concurrency architecture. |
