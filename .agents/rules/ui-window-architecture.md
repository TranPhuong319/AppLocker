# macOS Window Architecture & Platform Integrity Guidelines

## macOS Platform Integrity & Pure AppKit Skeleton

- **macOS Native App Architecture (Anti-iPadification)**:
  - AppLocker is a first-class macOS citizen, NOT a blown-up iPad app.
  - Must provide AppKit Menu Bar commands (`AppDelegate.setupEditMenu()` with `⌘,` Settings, `⌘W` Close, `⌘H` Hide, `⌘Q` Quit gated to Welcome in Release, Edit shortcuts), global Carbon hotkeys (`HotKeyManager`), right-click Context Menus (`.contextMenu`), and full keyboard tab-navigation.

- **Strict AppKit Boundary & Window Surface Rules**:
  - AppKit is strictly forbidden from doing anything except providing a clean, chrome-bridging window skeleton (`NSWindow`, `NSWindowController`).
  - **Window Surface Distinction (Opaque vs. Floating Glass)**:
    1. *Settings & Document Windows (`fullSizeContentView` + Scrolling)*: MUST set `isOpaque = true` and `backgroundColor = .windowBackgroundColor` (or system canvas). Window Server's native titlebar blur engine **requires an opaque canvas** to calculate blur over scrolling content. Setting `.clear` on scrolling windows destroys the blur shader, causing transparent bleed-through to the desktop/IDE and text collisions.
    2. *Floating Popups & Auth Dialogs (BatchAuth, Welcome)*: May use `isOpaque = false` and `backgroundColor = .clear` when rendered with pure SwiftUI custom floating material layers.
  - **SwiftUI NavigationSplitView Toolbar Bridging Mandate**:
    - **Absolute Ban on `NSWindow(contentViewController:)` for NavigationSplitView**: Initializing `NSWindow(contentViewController: hostingController)` or manually assigning `window.toolbar = NSToolbar(...)` causes AppKit to hijack toolbar ownership, completely suppressing the native sidebar toggle button `[ | ]` (`com.apple.SwiftUI.navigationSplitView.toggleSidebar`).
    - **Mandatory `contentView` Pattern**: Windows hosting `NavigationSplitView` MUST be initialized via `WindowManager.createWindow(contentView: hostingController.view, configuration: config)` (using `NSWindow(contentRect:styleMask:backing:defer:)`). This allows SwiftUI's AppKit adapter to directly install the native `[ | ]` toggle, `splitViewSeparator`, and bridge toolbar items and `.navigationTitle(...)`.
  - **Mandatory Skeleton Configuration**:
    - `styleMask` MUST include `.fullSizeContentView` so SwiftUI canvas expands across the entire window.
    - `titleVisibility = .visible` for windows utilizing `.navigationTitle(...)` in the toolbar (avoid `.hidden` which forcibly suppresses the title).
    - `titlebarSeparatorStyle = .none` (MANDATORY: permanently eliminates AppKit's automatic 1px divider line when scrolling, preserving seamless optical continuity between titlebar and content).
    - `isMovableByWindowBackground = false` (dragging strictly isolated to SwiftUI `WindowDragArea`).
    - On `NSHostingController`, enable `sceneBridgingOptions = [.toolbars, .title]` for windows bridging SwiftUI toolbars/titles (`SettingsWindowController`, `AppListWindowController`, `BatchAuthWindowController`, `WelcomeWindowController`). Pure custom-chrome windows with no toolbar/titlebar bridging (`AboutWindowController`) use `sceneBridgingOptions = []` and `sizingOptions = [.minSize, .maxSize, .intrinsicContentSize]`. For two-column resizable windows (`NavigationSplitView`), leave `sizingOptions = []` and enforce limits strictly via `window.minSize` and `windowWillResize(_:to:)` to prevent `NSHostingController` from overriding `window.minSize`.
    - For windows without toolbar items (`BatchAuthWindowController`, `WelcomeWindowController`), assigning an empty `window.toolbar = NSToolbar(identifier: ...)` alongside an empty SwiftUI `.toolbar { }` preserves squircle corners without bordered pill items.
    - **Preview vs. Live Window Chrome Parity**: Xcode `#Preview` does not attach `NSWindowController`'s empty `NSToolbar`, which changes top safe-area height. Do NOT remove view-level top compensation (such as `.padding(.top, -10)` in `BatchAuthView`) based solely on `#Preview` clipping without verifying the live `NSWindow` rendering.
    - All windows MUST be created via `WindowManager.createWindow`.

- **Unified Toolbar & NavigationSplitView Architecture**:
  - *Native Sidebar Toggle & Fluid Detail Layout*:
    - NEVER lock or disable sidebar collapsing (`canCollapse = false` or `columnVisibility: .constant(.all)`). Always allow `NavigationSplitView` to natively manage the sidebar toggle button (`[ | ]`), which automatically anchors next to the Traffic Lights in the sidebar column.
    - **Zero Rigid Constraints on Detail Columns**: NEVER assign `.frame(minWidth: ...)` / `.frame(minHeight: ...)` to the detail view or wrap `NavigationSplitView` in an outer `.frame(minWidth: ...)`. Placing `minWidth`/`minHeight` on child views causes AppKit's `NSSplitView` translation animation to violently push detail content outside the window frame during slide-in, triggering spurious vertical window height stretching via `NSHostingController` sizing passes, an abrupt layout snap (jitter), and macOS's emergency toolbar overflow chevron (`>>`). Detail views MUST use fluid layout (`.frame(maxWidth: .infinity, maxHeight: .infinity)`).
    - **Window-Level `minSize` & Toolbar Headroom**: Window minimum dimensions MUST be enforced strictly at the `NSWindow` level (`config.minSize = WindowLayout.settingsMinSize`, minimum $\ge 680\text{pt}$ for two-column settings windows). This mathematically guarantees safe minimum detail width ($\text{Detail minWidth} = \text{Window minWidth} - \text{Sidebar maxWidth}$) without inner constraint collision and provides sufficient toolbar headroom so toolbar items never overflow to trigger `>>`.
  - *Sidebar Tracking Separator*: Let AppKit natively coordinate the vertical divider between sidebar and detail content across resizes via `NSToolbarSidebarTrackingSeparatorItemIdentifier`.
  - *Compact Single-Line Titlebar*: Keep `.navigationTitle(...)` single-line; place section descriptions in the content layer (subtitles expand toolbar height from ~48pt to ~56–60pt, misaligning with the sidebar; `.navigationSubtitle` is banned via SwiftLint).
  - *Vertical Top Alignment in Detail Columns*:
    - The first element of the sidebar and the top edge of the detail view content should visually align.
    - When native `Form` containers in `NavigationSplitView` detail columns introduce an unwanted system top inset (~16pt), `.padding(.top, -16)` and `.topLeading` alignment may be applied ONLY while the active view actually renders a `Form` (e.g. via `usesGroupedForm` — exclude `ContentUnavailableView` states such as locked `SecuritySettingsTab` as well as `Activity`/`Diagnostics`).
  - *No Fake Material Overlays for Toolbars*:
    - NEVER place a manual `Rectangle().fill(.material)` or `.mask(LinearGradient(...))` as an overlay to simulate a toolbar. In Dark Mode, `Material` has intrinsic luminosity that creates a visible, contrasting gray box at rest and produces an unnatural, blurry color fog when saturated content scrolls underneath.
    - Rely 100% on native AppKit Window Server titlebar blur achieved via `fullSizeContentView` + `titlebarSeparatorStyle = .none` + native `NSToolbar` over `windowBackgroundColor`.
  - *Ponytail Navigation Rule*: Do NOT inject `.searchable(...)` into sidebars with $\le 6$ fixed navigation items. Search fields in compact sidebars create visual clutter without providing usability benefits.

- **Scrollable Header Optical Blur vs. Strict Clipping Patterns**:
  - *Pattern A (Native Titlebar Optical Blur)*: For headers with scrollable content passing underneath, extend the scroll view to the window boundary (`.ignoresSafeArea(edges: .top)`) and configure `window.titlebarSeparatorStyle = .none`. macOS Window Server automatically renders hardware-accelerated optical blur over the scrolling content without line dividers or color bleeding.
  - *Pattern B (Clean Bound / Zero Collision)*: Use `VStack(spacing: 0) { headerView; ScrollView { ... }.clipped() }` to strictly confine the scrolling area below the header without content peeking into the titlebar or traffic lights.

---

## Modern UI State Management Rules

- **Observation Framework for UI State**: Use `@Observable` for macOS 14+ view state models and structured `Task` + `Task.sleep` cancellation for debouncing (legacy `Combine` / `ObservableObject` / `@Published` are banned via SwiftLint).
