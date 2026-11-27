# Liquid Glass & macOS UI Design Guidelines

## 1. Materials & Layer Architecture

- **Functional Layer vs. Content Layer**:
  - **Floating Functional Layer (`.glassEffect`)**: Strictly reserve Liquid Glass for navigation chrome and floating controls (toolbars, sidebars, floating action pills).
  - **Content Layer (`Material`)**: Use native standard materials (`Material`, `.ultraThinMaterial`, `NSVisualEffectView`) for cards, panels, and lists. NEVER put Liquid Glass on static content cards or list rows.
  - **Window Blending Harmony**: On opaque canvas windows (`isOpaque = true`, `windowBackgroundColor`), do NOT use `.behindWindow` blending. Rely on Window Server native titlebar blur. Use `.withinWindow` blending only when dividing internal content layers.
- **Native Platform First**: Rely on native SwiftUI components (`NavigationSplitView`, `Form`, `List`, `.toolbar`) which adopt system materials automatically.
- **Grouped `Form` Control Layout (`macOS 14+`)**:
  - **Inline Subtitles vs. Separated Description Rows**: Prefer inline subtitles inside a control's label (`VStack(alignment: .leading)`) in multi-control sections so automatic row dividers only separate distinct settings. Separate a description into its own bottom row (with a divider above it) when the primary row already has a leading icon or status line (e.g. `Background Agent Status`, `Application Lock`) where an inline caption would break left alignment or stack 3+ text styles.
  - **`Slider` Label Column Alignment**: Always apply `.labelsHidden()` to `Slider` inside `.formStyle(.grouped)` when rendering a custom header above it, so SwiftUI does not reserve an empty leading label column.
- **Sheets & Popovers**: Never inject custom visual effect views or redundant background materials inside native sheets/popovers; system chrome already manages vibrancy.

---

## 2. Colors, Contrast & Typography

- **Semantic System Colors**: NEVER hardcode static colors (`Color.black`, `Color.white`, hex values) for surfaces or text. Always use semantic colors (`Color.primary`, `Color.secondary`, `Color(nsColor: .windowBackgroundColor)`, `Color(nsColor: .separatorColor)`).
- **Accessible State Signifiers**: Pair colors with clear icons or text (e.g. checkmark, warning triangle); never rely on color alone to indicate error or status.
- **Dynamic Typography**: Prefer semantic font styles (`.headline`, `.subheadline`, `.body`, `.caption`) over hardcoded point sizes. Avoid defensive `.lineLimit(1)` that clips localized text.

---

## 3. Interaction, Modals & Safety

- **Pointer & Hover**: Provide clear hover/pointer feedback (`.onHover`, or `.pointerStyle` gated with `#available(macOS 15.0, *)`) on interactive custom controls.
- **Destructive Actions (SwiftUI, AppKit `NSAlert`, Touch Bar)**:
  - *SwiftUI*: Use `Button(role: .destructive)` with `.tint(.red)`, mandatory confirmation alerts for non-undoable operations, and **never** assign `.keyboardShortcut(.defaultAction)` to a destructive button.
  - *AppKit `NSAlert` (`AlertShow`)*: Set `destructiveIndex` (`button.hasDestructiveAction = true`) and leave `defaultIndex: nil` per Apple macOS HIG so the destructive button stays red, `Cancel` stays neutral gray (not accent blue), and `Escape` (`"\u{1b}"`) works on localized cancel titles (never set `defaultIndex == cancelIndex`, which turns `Cancel` blue and overrides `"\u{1b}"`).
  - *Touch Bar (`NSButtonTouchBarItem`)*: `NSButtonTouchBarItem` has no `.destructive` role property; use `bezelColor: .systemRed` (never `.controlAccentColor`) for destructive Touch Bar buttons.
- **Dialog Button Symmetry**: Group `[Cancel][Primary]` on the trailing edge for left-aligned sheets (`AddAppSheet`, `DeleteQueueSheet`, `MissingAppsSheet`). For centered onboarding windows (`WelcomeView`), use equal 50/50 full-width buttons aligned to content edges; for compact floating auth dialogs (`BatchAuthView`), keep symmetric leading/trailing equal-width corners.
- **Self-Contained Modals**: Reserve sheets for atomic tasks (settings, adding items). Always provide explicit dismiss buttons (`Done` / `Cancel`) and discard prompts if modified.

---

## 4. Purposeful Delight & SF Symbols

- **Deliberate State Transitions (Magic Replacement)**:
  - When an SF Symbol toggles or updates state (e.g. `lock.fill` $\leftrightarrow$ `lock.open.fill`, `doc.on.doc` $\leftrightarrow$ `checkmark`), use `.magicSymbolReplace()` from `WindowLayout.swift` (uses `.replace.magic(fallback: .downUp.byLayer)` on macOS 15+ and `.replace.downUp.byLayer` on macOS 14).
- **Directional Numeric Transitions**:
  - When dynamic numbers change (counters, queue badges), apply `.contentTransition(.numericText(value: Double(count)))` with `.monospacedDigit()`.
- **Restraint Over Clutter**:
  - Add discrete effects (`.bounce`, `.rotate`) only to acknowledge explicit user actions (enqueuing, refreshing). Never apply decorative micro-effects that distract from content or cause continuous CPU/GPU wakeups.
- **Deployment Target Symbol Verification (`macOS 14+`)**:
  - Verify every SF Symbol against `MACOSX_DEPLOYMENT_TARGET = 14.0` (e.g. via `CoreGlyphs.bundle/Contents/Resources/name_availability.plist`) before committing. Never use macOS 15+ symbols (`arrow.trianglehead.2.clockwise.rotate.90`, `document.on.document`, `text.page.slash`) without `#available(macOS 15.0, *)` fallbacks; prefer macOS 14-compatible equivalents (`arrow.triangle.2.circlepath`, `doc.on.doc`, `doc.text.magnifyingglass`).

