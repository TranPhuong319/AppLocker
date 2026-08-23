# Feature Specification: Native Numeric Text Content Transition

**Feature Branch**: `005-native-numeric-transition`

**Created**: 2026-08-23

**Status**: Draft

**Input**: User description: "±Thay đổi: Sửa code loại bỏ phần .numericTextTransition thủ công, thay thế thành .numericTextTransition mặc định contentTransition(.numericText(value: value)) (bỏ flágs if available macOS 14"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Fluid Numeric Counter Animations in UI (Priority: P1)

Users viewing item counts, selected badges, and authorization countdown timers across AppLocker views experience fluid, seamless animated transitions whenever numerical values increase or decrease, without visual stutter or layout jumps.

**Why this priority**: Core visual feedback mechanism for selection states (Add App Sheet, Batch Auth View) and critical countdown feedback (Security Settings, Batch Auth Timeout).

**Independent Test**: Can be fully tested by selecting/deselecting apps in Add App Sheet or Batch Auth View and observing the numeric badge transition smoothly between values.

**Acceptance Scenarios**:

1. **Given** the user is on the Add App Sheet with multiple applications listed, **When** the user checks or unchecks apps, **Then** the selected counter badge animates smoothly to reflect the updated count using the native numeric transition.
2. **Given** the user is viewing the Batch Authorization sheet, **When** items are toggled or the countdown timer ticks down, **Then** numeric text transitions cleanly to the next value without clipping or jumpy re-layouts.
3. **Given** the user is in Security Settings configuring the auto-lock timeout, **When** countdown seconds update, **Then** the timer text updates with continuous numeric animation.

---

### User Story 2 - Elimination of Redundant Platform Availability Branching (Priority: P2)

Developers and maintainers have a cleaner, leaner codebase where modern platform APIs are adopted directly without legacy runtime availability checks (`#available(macOS 14.0, *)`) or redundant wrapper extensions, in accordance with the project constitution (YAGNI & Native Platform First).

**Why this priority**: Reduces maintenance overhead, eliminates dead compatibility branches, and adheres directly to AppLocker Constitution Principle I.

**Independent Test**: Can be verified by auditing the view modifier helpers to ensure no custom `.numericTextTransition` wrapper exists and standard platform `.contentTransition(.numericText(...))` is applied directly at call sites.

**Acceptance Scenarios**:

1. **Given** the deployment target is macOS 14.0+, **When** numeric text views are rendered, **Then** standard platform content transition APIs are used directly without wrapper indirection.
2. **Given** the refactored view files, **When** compiling and running static analysis, **Then** zero availability check warnings or unused modifier definitions remain.

---

### Edge Cases

- **Rapid Counter Increments/Decrements**: When selecting/deselecting all items rapidly, the numeric transition must interpolate correctly between values without glitching or overlapping text.
- **Zero Values**: Transitioning to or from 0 (e.g. 0 items selected) must render cleanly without empty badge artifacts.
- **Countdown Directions**: Countdowns (e.g., in batch authorization countdown timer) must maintain correct directional numeric rolling (`countsDown: true`).

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Application numeric text views (selected count badges in `AddAppSheet`, `BatchAuthView`, and countdown displays in `SecuritySettingsTab`) MUST apply native platform numeric content transitions directly.
- **FR-002**: Redundant custom wrapper methods (such as custom `.numericTextTransition(value:)`) MUST be completely removed in favor of direct standard library/framework modifiers.
- **FR-003**: Obsolete `#available(macOS 14.0, *)` runtime availability branching for numeric text transitions MUST be eliminated since the deployment target is macOS 14.0+.
- **FR-004**: All numeric animations MUST maintain existing visual styling, typography, and layout alignment across dark and light appearances.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% of numeric counter call sites in the application utilize direct native `.contentTransition(.numericText(...))` modifiers.
- **SC-002**: Codebase complexity is reduced by eliminating custom transition wrapper functions and removing 100% of redundant macOS 14 runtime availability checks for numeric text transitions.
- **SC-003**: Zero visual regressions during badge updates and countdown timer intervals across all supported macOS versions (macOS 14.0+).

## Assumptions

- The minimum deployment target for AppLocker is macOS 14.0 (`Sonoma`), making `.contentTransition(.numericText(...))` available universally without runtime fallback logic.
- Standard SwiftUI `.contentTransition(.numericText(value:))` and `.contentTransition(.numericText(countsDown:))` fully satisfy the animation requirements of all existing views.
