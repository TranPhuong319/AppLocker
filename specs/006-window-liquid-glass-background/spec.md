# Feature Specification: Window Liquid Glass Background Enhancement

**Feature Branch**: `006-window-liquid-glass-background`

**Created**: 2026-08-23

**Status**: Draft

**Input**: User description: "Thay đổi: Gia tăng độ liquid Glass ở background ở window cho AppLocker/Appearance/View/MainUI/ContentView.swift , AppLocker/Appearance/View/BatchAuth/BatchAuthView.swift , AppLocker/Appearance/View/MainUI/Sheets/AddAppSheet.swift , AppLocker/Appearance/View/MainUI/Sheets/DeleteQueueSheet.swift và AppLocker/Appearance/View/Settings/SettingsView.swift (±Tuỳ chọn)"

## Clarifications

### Session 2026-08-23
- Q: How should the enhanced Liquid Glass background effect be applied to the Settings window? → A: Option C: Keep Settings window with its current default appearance unchanged; only apply enhanced Liquid Glass background to ContentView, BatchAuthView, AddAppSheet, and DeleteQueueSheet.
- Q: Which material and visual effect approach should be used to increase the Liquid Glass depth across target windows and sheets? → A: Option A: High-translucency frosted glass with behind-window blending (`.underWindowBackground` / `.hudWindow`) providing vibrant optical background blur and subtle edge highlight refraction, matching modern macOS notification/system alert banner aesthetics.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Immersive Translucent Liquid Glass Window Backgrounds (Priority: P1)

Users opening the main application window (`ContentView`) and the batch authorization popup (`BatchAuthView`) experience a modern, premium translucent Liquid Glass visual effect that dynamically blends with macOS desktop wallpapers and window surroundings while maintaining crisp text legibility and contrast.

**Why this priority**: The main app list and authorization dialog are the primary user-facing interfaces where visual polish and macOS design harmony are most prominent.

**Independent Test**: Launch the main app window and batch authorization dialog over varied desktop wallpapers; verify the increased translucency and vibrant frosted glass background without content readability loss.

**Acceptance Scenarios**:

1. **Given** the user opens the main window (`ContentView`), **When** viewed over bright or dark wallpapers, **Then** the background displays an enhanced translucent material effect with high vibrancy and no opaque cutoff borders.
2. **Given** an intercepted application triggers the authorization dialog (`BatchAuthView`), **When** the dialog appears floating on screen, **Then** the window presents a cohesive translucent Liquid Glass backdrop with clear separation between content headers, list items, and action buttons.

---

### User Story 2 - Consistent Translucency for Modal Sheets (Priority: P2)

Users invoking secondary modal sheets (`AddAppSheet` and `DeleteQueueSheet`) observe unified Liquid Glass depth and materials matching the primary window styling, avoiding abrupt visual shifts between parent windows and attached sheets.

**Why this priority**: Consistency between main windows and modal sheets prevents visual dissonance during everyday workflows (adding apps to lock or unlocking queued apps).

**Independent Test**: Open the Add Application sheet and Delete Queue sheet; verify the background material exhibits increased translucency and consistent edge-to-edge backdrop blending.

**Acceptance Scenarios**:

1. **Given** the user clicks the '+' button to open `AddAppSheet`, **When** the sheet slides in, **Then** the sheet background reflects the enhanced Liquid Glass material seamlessly.
2. **Given** items exist in the deletion queue and the user opens `DeleteQueueSheet`, **When** navigating the queue, **Then** the background maintains identical translucency and blur characteristics.

---

### Edge Cases

- **High Contrast / Accessibility Settings**: When the user enables "Reduce Transparency" in macOS System Settings, backgrounds must gracefully fall back to solid/opaque system materials to respect accessibility standards.
- **Light & Dark Mode Dynamic Switching**: Translucent glass backgrounds must instantly adapt when macOS switches between Light and Dark appearance without flashing or artifacting.
- **Window Resizing and Repositioning**: Dynamic backdrop blur must update in real-time during live resize and window dragging without stutter.
- **Nested Glass Elements**: Child components (search capsules, item cards, action bars) must avoid muddy double-darkening (glass-on-glass artifacting) against the enhanced window background.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The main window (`ContentView`), batch authorization window (`BatchAuthView`), and modal sheets (`AddAppSheet`, `DeleteQueueSheet`) MUST apply enhanced Liquid Glass background translucency with active behind-window blending.
- **FR-002**: The settings window (`SettingsView`) MUST remain unchanged in its existing native appearance.
- **FR-003**: Window background visual effect layers MUST extend edge-to-edge (`ignoresSafeArea`) without hard background cutoff lines.
- **FR-004**: The visual styling MUST preserve strict text and icon legibility across both Light and Dark macOS appearances.
- **FR-005**: Child UI elements (search bars, action capsules, list rows) MUST coordinate with the enhanced background to prevent optical darkening and glass-on-glass distortion.
- **FR-006**: All window controllers hosting the enhanced views MUST configure window opacity, clear background coloring, and titlebar transparency to support full-depth Liquid Glass rendering.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% of target views (`ContentView`, `BatchAuthView`, `AddAppSheet`, `DeleteQueueSheet`) render with enhanced Liquid Glass translucency.
- **SC-002**: `SettingsView` retains its existing appearance without regression.
- **SC-003**: Zero visual artifacts (no dark box clipping, no unintended double-layered opaque fills) across both Light and Dark mode appearances.
- **SC-004**: Background material responds immediately (zero rendering lag) when windows are dragged or resized over complex wallpapers.

## Assumptions

- The app targets macOS 14.0+ where native visual effect materials, behind-window blending, and modern SwiftUI material backgrounds are fully supported.
- System accessibility preferences (such as "Reduce Transparency") are automatically respected by platform visual effect materials.

