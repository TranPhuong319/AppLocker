# Liquid Glass & macOS UI Design Guidelines

## 1. Materials & Layer Architecture

- **Functional Layer vs. Content Layer**:
  - **Floating Functional Layer (`.glassEffect`)**: Strictly reserve Liquid Glass for navigation chrome and floating controls (toolbars, sidebars, floating action pills).
  - **Content Layer (`Material`)**: Use native standard materials (`Material`, `.ultraThinMaterial`, `NSVisualEffectView`) for cards, panels, and lists. NEVER put Liquid Glass on static content cards or list rows.
  - **Window Blending Harmony**: On opaque canvas windows (`isOpaque = true`, `windowBackgroundColor`), do NOT use `.behindWindow` blending. Rely on Window Server native titlebar blur. Use `.withinWindow` blending only when dividing internal content layers.
- **Native Platform First**: Rely on native SwiftUI components (`NavigationSplitView`, `Form`, `List`, `.toolbar`) which adopt system materials automatically.
- **Sheets & Popovers**: Never inject custom visual effect views or redundant background materials inside native sheets/popovers; system chrome already manages vibrancy.

---

## 2. Colors, Contrast & Typography

- **Semantic System Colors**: NEVER hardcode static colors (`Color.black`, `Color.white`, hex values) for surfaces or text. Always use semantic colors (`Color.primary`, `Color.secondary`, `Color(nsColor: .windowBackgroundColor)`, `Color(nsColor: .separatorColor)`).
- **Accessible State Signifiers**: Pair colors with clear icons or text (e.g. checkmark, warning triangle); never rely on color alone to indicate error or status.
- **Dynamic Typography**: Prefer semantic font styles (`.headline`, `.subheadline`, `.body`, `.caption`) over hardcoded point sizes. Avoid defensive `.lineLimit(1)` that clips localized text.

---

## 3. Interaction, Modals & Safety

- **Pointer & Hover**: Provide clear pointer feedback (`.onHover`, `.pointerStyle`) on interactive custom controls.
- **Destructive Actions**: Use `role: .destructive`, red accent, and mandatory confirmation dialogues (`confirmationDialog` / `alert`) for non-undoable operations.
- **Self-Contained Modals**: Reserve sheets for atomic tasks (settings, adding items). Always provide explicit dismiss buttons (`Done` / `Cancel`) and discard prompts if modified.

---

## 4. Purposeful Delight & SF Symbols

- **Deliberate State Transitions (Magic Replacement)**:
  - When an SF Symbol toggles or updates state (e.g. `lock.fill` $\leftrightarrow$ `lock.open.fill`, `doc.on.doc` $\leftrightarrow$ `checkmark`), use `.contentTransition(.symbolEffect(.replace.magic(fallback: .downUp.byLayer)))`.
- **Directional Numeric Transitions**:
  - When dynamic numbers change (counters, queue badges), apply `.contentTransition(.numericText(value: Double(count)))` with `.monospacedDigit()`.
- **Restraint Over Clutter**:
  - Add discrete effects (`.bounce`, `.rotate`) only to acknowledge explicit user actions (enqueuing, refreshing). Never apply decorative micro-effects that distract from content or cause continuous CPU/GPU wakeups.

