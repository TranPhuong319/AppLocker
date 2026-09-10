# Liquid Glass & macOS UI Design Guidelines

## Liquid Glass & UI Presentation

- **No Custom Glass-on-Glass Layering**:
  - Rely on Apple native components (`NavigationSplitView`, `NavigationStack`, `Form`, `List`, `.toolbar`) to adopt macOS Liquid Glass material automatically.
  - Avoid wrapping custom background modifiers (`.liquidGlassBackground`, `.liquidGlassCard`) over standard containers to prevent visual fragmentation and dark box artifacts.
- **Traffic Light Margin & Inset**:
  - Always provide top padding (`~14pt`) and leading inset (`54–68pt`) in top window headers to cleanly isolate traffic light buttons (close/minimize/zoom) from clipping window corners or content text.
- **Titlebar Drag Isolation**:
  - Enforce `isMovableByWindowBackground = false` on `NSWindow` instances.
  - Wrap top header views in `WindowDragArea` using native `window.performDrag(with:)` so dragging is strictly isolated to the titlebar region.
- **Pure AppKit Skeleton & 100% SwiftUI UI Ownership (Mandatory)**:
  - **Strict AppKit Boundary (Window Frame Only)**:
    - AppKit is strictly forbidden from doing anything except providing a 100% transparent, chrome-bridging window skeleton (`NSWindow`, `NSWindowController`).
    - **Absolute AppKit Bans**:
      1. NEVER set `backgroundColor` on `NSWindow` or `NSView` to anything other than `.clear`, and NEVER set `isOpaque = true`.
      2. NEVER manipulate `CALayer` or view hierarchies directly on `NSHostingView` (`wantsLayer`, `layer.backgroundColor`).
      3. NEVER intercept window sizing or resizing in AppKit delegates (`windowWillResize`). All frame bounds, min/max dimensions, and aspect ratios must be declared natively in SwiftUI via `.frame(...)`.
      4. NEVER render static AppKit window titles (`titleVisibility = .hidden`). Window titles belong 100% to SwiftUI (`.navigationTitle(...)`).
      5. NEVER inject decorative AppKit controls or visual containers (`NSVisualEffectView`, `NSBox`, `NSButton`).
    - **Mandatory Skeleton Configuration**:
      - `styleMask` MUST include `.fullSizeContentView` so SwiftUI canvas expands across the entire window.
      - `titlebarAppearsTransparent = true` and `titleVisibility = .hidden`.
      - `isMovableByWindowBackground = false` (dragging strictly isolated to SwiftUI `WindowDragArea`).
      - On `NSHostingController`, ALWAYS enable `sceneBridgingOptions = [.toolbars, .title]` AND `sizingOptions = [.minSize, .maxSize, .intrinsicContentSize]`.
      - ALWAYS assign a dummy `window.toolbar = NSToolbar(identifier: ...)` at the AppKit level solely to activate SwiftUI `.toolbar` and titlebar bridging.
      - All windows MUST be created via `WindowManager.createWindow` using the transparent skeleton defaults.
- **Scrollable Header Optical Blur vs. Strict Clipping Patterns**:
  - *Pattern A (Optical Blur Behind Header)*: Use `ScrollView { ... }.safeAreaInset(edge: .top, spacing: 0) { headerView }` where `headerView` has `.background(Rectangle().fill(.ultraThinMaterial.opacity(0.6)).ignoresSafeArea(edges: .top))`. Note: in this pattern, content scrolls continuously underneath the header all the way to `y = 0`.
  - *Pattern B (Clean Bound / Zero Collision)*: Use `VStack(spacing: ...) { headerView; ScrollView { ... }.clipped() }` to strictly confine the scrolling area below the header without content peeking into the titlebar or traffic lights.

---

## Modern State Management Rules

- **Observation Framework over Combine for UI State**:
  - For macOS 14+ view state models, prefer the Swift `@Observable` macro over `ObservableObject` / `@Published` to reduce boilerplate and optimize granular view re-rendering.
  - Reserve `Combine` strictly for complex asynchronous stream transformations (e.g. `.debounce`, `.throttle`, `.combineLatest`).
