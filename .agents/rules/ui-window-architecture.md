# macOS Window Architecture & Platform Integrity Guidelines

## macOS Platform Integrity & Pure AppKit Skeleton

- **macOS Native App Architecture (Anti-iPadification)**:
  - AppLocker is a first-class macOS citizen, NOT a blown-up iPad app.
  - Must provide comprehensive Menu Bar commands (`CommandMenu`, standard shortcuts like `⌘,` for Settings, `⌘W` for Close, `⌘R` for Refresh), right-click Context Menus (`.contextMenu`), and full keyboard tab-navigation.

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
    - On `NSHostingController`, ALWAYS enable `sceneBridgingOptions = [.toolbars, .title]` AND `sizingOptions = [.minSize, .maxSize, .intrinsicContentSize]`.
    - For non-interactive windows without SwiftUI toolbars (`BatchAuthWindowController`, `WelcomeWindowController`, `AboutWindowController`), assigning an empty `window.toolbar = NSToolbar(identifier: ...)` at AppKit level remains valid to force squircle corners without pill items.
    - All windows MUST be created via `WindowManager.createWindow`.

- **Unified Toolbar & NavigationSplitView Architecture**:
  - *Native Sidebar Toggle & Fluid Detail Layout*:
    - NEVER lock or disable sidebar collapsing with `SidebarCollapsePreventer`, canCollapse = false, or `columnVisibility: .constant(.all)`. Always allow `NavigationSplitView` to natively manage the sidebar toggle button (`[ | ]`), which automatically anchors next to the Traffic Lights in the sidebar column.
    - **Zero Rigid Constraints on Detail Columns**: NEVER assign `.frame(minWidth: ...)` / `.frame(minHeight: ...)` to the detail view or wrap `NavigationSplitView` in an outer `.frame(minWidth: ...)`. Placing `minWidth`/`minHeight` on child views causes AppKit's `NSSplitView` translation animation to violently push detail content outside the window frame during slide-in, triggering spurious vertical window height stretching via `NSHostingController` sizing passes, an abrupt layout snap (jitter), and macOS's emergency toolbar overflow chevron (`>>`). Detail views MUST use fluid layout (`.frame(maxWidth: .infinity, maxHeight: .infinity)`).
    - **Window-Level `minSize` & Toolbar Headroom**: Window minimum dimensions MUST be enforced strictly at the `NSWindow` level (`config.minSize = WindowLayout.settingsMinSize`, minimum $\ge 680\text{pt}$ for two-column settings windows). This mathematically guarantees safe minimum detail width ($\text{Detail minWidth} = \text{Window minWidth} - \text{Sidebar maxWidth}$) without inner constraint collision and provides sufficient toolbar headroom so toolbar items never overflow to trigger `>>`.
  - *Sidebar Tracking Separator*: Let AppKit natively coordinate the vertical divider between sidebar and detail content across resizes via `NSToolbarSidebarTrackingSeparatorItemIdentifier`.
  - *Compact Single-Line Titlebar*:
    - Keep `.navigationTitle(...)` strictly single-line.
    - NEVER inject `.navigationSubtitle(...)` into the toolbar of settings or management windows. A 2-story subtitle expands toolbar height from compact (~48pt) to ~56–60pt, causing an unaligned, lopsided height mismatch with the 1-story sidebar. Subtitles or section descriptions belong strictly in the content layer (e.g., section headers or body text).
  - *Vertical Top Alignment in Detail Columns*:
    - The first element of the sidebar and the top edge of the detail view content should visually align.
    - When native `Form` containers in `NavigationSplitView` detail columns introduce an unwanted system top inset (~16pt), `.padding(.top, -16)` may be applied to offset it. Do not apply negative padding unconditionally if content uses standard `ScrollView` or custom stacks where no default inset exists.
  - *No Fake Material Overlays for Toolbars*:
    - NEVER place a manual `Rectangle().fill(.material)` or `.mask(LinearGradient(...))` as an overlay to simulate a toolbar. In Dark Mode, `Material` has intrinsic luminosity that creates a visible, contrasting gray box at rest and produces an unnatural, blurry color fog when saturated content scrolls underneath.
    - Rely 100% on native AppKit Window Server titlebar blur achieved via `fullSizeContentView` + `titlebarSeparatorStyle = .none` + native `NSToolbar` over `windowBackgroundColor`.
  - *Ponytail Navigation Rule*: Do NOT inject `.searchable(...)` into sidebars with $\le 6$ fixed navigation items. Search fields in compact sidebars create visual clutter without providing usability benefits.

- **Scrollable Header Optical Blur vs. Strict Clipping Patterns**:
  - *Pattern A (Native Titlebar Optical Blur)*: For headers with scrollable content passing underneath, extend the scroll view to the window boundary (`.ignoresSafeArea(edges: .top)`) and configure `window.titlebarSeparatorStyle = .none`. macOS Window Server automatically renders hardware-accelerated optical blur over the scrolling content without line dividers or color bleeding.
  - *Pattern B (Clean Bound / Zero Collision)*: Use `VStack(spacing: 0) { headerView; ScrollView { ... }.clipped() }` to strictly confine the scrolling area below the header without content peeking into the titlebar or traffic lights.

---

## Modern UI State Management Rules

- **Observation Framework over Combine for UI State**:
  - For macOS 14+ view state models, prefer the Swift `@Observable` macro over `ObservableObject` / `@Published` to reduce boilerplate and optimize granular view re-rendering.
  - Reserve `Combine` strictly for complex asynchronous stream transformations (e.g. `.debounce`, `.throttle`, `.combineLatest`).
