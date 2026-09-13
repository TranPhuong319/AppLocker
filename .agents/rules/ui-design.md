# Liquid Glass & macOS UI Design Guidelines

## Apple HIG Materials & Liquid Glass Architecture

- **Functional Layer (Liquid Glass) vs. Content Layer (Standard Materials)**:
  - **Floating Functional Layer**: Strictly reserve Liquid Glass for navigation and controls (toolbars, sidebars, tab bars, floating action pills). Liquid Glass floats above the content layer, allowing underlying content to peek and scroll through while maintaining crisp control legibility.
  - **Strict Content Layer Ban**: NEVER use Liquid Glass in the content layer (e.g., list row backgrounds, content cards, static panel backgrounds). Overusing glass in content creates visual fragmentation, dark-box artifacts, and confusing hierarchy. Use Standard Materials (`Material`, `NSVisualEffectMaterial`) for content-layer structure.
  - **Transient Interaction Exception**: Controls within the content layer with temporary interactive states (such as active sliders, toggles, or scrubbers) may adopt Liquid Glass styling *only* while actively being manipulated to highlight interactivity.
  - **Use Liquid Glass Sparingly**: Rely on Apple native components (`NavigationSplitView`, `NavigationStack`, `Form`, `List`, `.toolbar`) to adopt Liquid Glass automatically. Limit custom `.glassEffect` to essential primary functional elements; overusing it distracts from core content.

- **Liquid Glass Variants (Regular vs. Clear)**:
  - **Regular Variant (Default)**: Automatically blurs and adjusts background luminosity. Mandatory for sidebars, popovers, alerts, dialogs, and components containing text.
  - **Clear Variant**: Highly translucent; ONLY use for components floating over visually rich media backgrounds (photos, video players).
  - **Dimming Layer Rule**: When using Clear Liquid Glass over bright content, always add a dark dimming layer with ~35% opacity behind the component to preserve text contrast and legibility (omit only if the background is inherently dark or provided by AVKit).

- **Standard Materials & Vibrancy in Content Layer**:
  - **Semantic Selection Over Apparent Color**: Choose materials (`ultraThin`, `thin`, `regular`, `thick`) based on semantic purpose and structural depth, NEVER based on temporary apparent color, because system settings (Dark Mode, High Contrast) dynamically change rendering.
    - *Thicker materials*: Use when high contrast is required for fine text and subtle iconography.
    - *Thinner materials*: Use to maintain ambient context of background content.
  - **Mandatory System Vibrancy**: Always use system vibrant colors (`.primary`, `.secondary`, `.tertiary`, `NSColor.labelColor`, etc.) on top of materials. Never use flat static colors that wash out under variable background brightness.
  - **macOS Blending Mode**: Consciously choose `NSVisualEffectBlendingMode`: `.behindWindow` for desktop-blended chrome/sidebars, and `.withinWindow` for content-layer division within the app canvas.

- **Adopting Liquid Glass Engineering & Layout Rules**:
  - **`GlassEffectContainer` for Rendering & Morphing**: When combining multiple custom Liquid Glass controls or action pills, ALWAYS group them within `GlassEffectContainer`. This optimizes GPU composition performance and enables fluid geometric morphing between adjacent glass shapes.
  - **Toolbar Item Hiding Rule (No Empty Glass Pills)**: When hiding an action in a toolbar, toggle the toolbar item itself (`NSToolbarItem.isHidden` in AppKit or conditional `.toolbar` item placement in SwiftUI). NEVER hide only the child view inside the item, as doing so leaves an empty Liquid Glass capsule/pill in the toolbar.
  - **No Redundant Materials in Popovers & Sheets**: System sheets and popovers natively adopt Liquid Glass and updated corner radii. NEVER inject custom `NSVisualEffectView` or `.background(.ultraThinMaterial)` inside popover/sheet content views, which creates muddy double-layered blurs.
  - **Concentric Curvature**: Shape radii of buttons, nested pills, and inner containers must align concentrically with the hardware and window boundary radius.
  - **Section Header Title-Style Capitalization**: Section headers in `List`, `Table`, and `Form` now adopt title-style capitalization natively. NEVER force all-caps strings (`.uppercased()`) in section titles; use standard Title Case strings.
  - **Icons & Accessibility Over Shared Backgrounds**: In toolbars and button groups that share a Liquid Glass background, prefer iconography over mixed text/icons for clarity, and ALWAYS attach `.accessibilityLabel(...)` to every icon.
  - **Scroll Edge Protection**: Ensure custom bars overlaying scroll views utilize scroll edge protection (`scrollEdgeEffectStyle(_:for:)` or our Optical Glass Scattering pattern) so text scrolling beneath controls doesn't degrade control contrast.

---

## Color, Contrast & Semantic Palette

- **Strict Semantic Color Mandate**:
  - NEVER hardcode hex or static RGB colors (`Color(hex: ...)`, `Color.black`, `Color.white`) for surfaces, controls, borders, or text.
  - ALWAYS use semantic system colors (`Color.primary`, `Color.secondary`, `Color(nsColor: .windowBackgroundColor)`, `Color(nsColor: .controlBackgroundColor)`, `Color(nsColor: .separatorColor)`) to guarantee flawless adaptation across Light Mode, Dark Mode, and High Contrast.
- **WCAG Contrast Ratios**:
  - Maintain a minimum contrast ratio of **4.5:1** for body text and **3:1** for large text, headers, and essential iconography.
- **Judicious Accent/Tint Usage**:
  - Use tint/accent color sparingly to signify primary interactivity or selected state. Overusing tint colors across decorative elements dilutes their communicative power and confuses users about what is clickable.
- **No Color-Only Signifiers**:
  - NEVER communicate status, errors, or critical state solely through color (e.g. green/red dots). Always pair color with descriptive text, tooltips, or distinct iconography (e.g. checkmark, warning triangle) to support color-blind users.

---

## Typography & Layout Adaptability

- **Semantic Text Styles**:
  - Prefer semantic styles (`.font(.title)`, `.font(.headline)`, `.font(.body)`, `.font(.caption)`) over hardcoded point sizes (`.font(.system(size: 16))`) to ensure proper optical scaling and accessibility responsiveness.
- **No Harmful Text Truncation**:
  - Avoid defensive `.lineLimit(1)` on vital labels, titles, or status messages. Allow multi-line wrapping and vertical expansion so translated strings and large text sizes do not end up clipped with ellipsis (`...`).
- **Section Header Casing**:
  - Use standard Title-Style Capitalization for Section headers in `List`, `Table`, and `Form`. Never force `.uppercased()` on headers.
- **Concentric Curvature Formula**:
  - Maintain visual continuity by ensuring inner nested corner radii are concentric with outer containers and window borders:
    $$\text{Radius}_{\text{inner}} = \text{Radius}_{\text{outer}} - \text{Padding}$$

---

## Interaction, Pointer & Modal Safety

- **Pointer Feedback & Hit Targets**:
  - Ensure interactive controls provide clear pointer hover states (`.onHover`, `.pointerStyle`) and adequate click bounds.
  - In touch contexts (or catalyst/touch-friendly elements), maintain a minimum interactive hit target of **$44 \times 44\text{pt}$**, expanding with `.contentShape(Rectangle())` if the visual icon is smaller.
- **Destructive Action Protection**:
  - Destructive actions (e.g. deleting items, resetting databases, revoking access) must use `role: .destructive`, red accenting, and a mandatory confirmation alert/dialogue (`confirmationDialog`, `alert`) if non-undoable.
  - NEVER position a destructive button directly adjacent to the primary positive action without confirmation safeguards.
- **Modal vs. In-Place Flow**:
  - Reserve modal sheets for self-contained, atomic tasks (settings, composition, item creation). Do not use sheets for continuous navigation or stack multiple modals.
  - Sheets must always provide explicit, unequivocal dismiss mechanisms (`Done` or `Cancel`).
  - Protect unsaved work: if a user attempts to dismiss a sheet with modified state, present a confirmation discard prompt.

---

## Accessibility (A11y) & System Settings Alignment

- **Mandatory Accessibility Labels on Icons**:
  - Every icon-only button (`Image(systemName: ...)`) MUST have an explicit `.accessibilityLabel("Action Name")` and, where appropriate, an `.accessibilityHint(...)`.
- **System Accessibility Override Compliance**:
  - Strictly rely on native materials (`.glassEffect`, `Material`, `NSVisualEffectView`) so the OS can automatically convert translucency to high-contrast opaque backgrounds when the user enables **Reduce Transparency** or **Increase Contrast**.
  - Check `@Environment(\.accessibilityReduceMotion)` before executing decorative physics animations, parallax, or aggressive shape morphing.
