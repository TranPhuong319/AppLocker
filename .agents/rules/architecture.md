# Clean Architecture & Platform API Guidelines

## Ponytail & Clean Architecture Guidelines

- **Inviolable Rule: Never Break Userspace Experience & Visual Integrity (Linus's Law)**:
  - Code refactoring, optimization, or linting cleanups MUST NEVER degrade, alter, or break the user-facing experience, feature behavior, UI visuals, glass materials, animations, or platform availability checks (`#available`).
  - **Zero Speculative Visual/Feature Stripping**: Do NOT remove visual treatments (e.g. Liquid Glass effects, `.ultraThinMaterial`, custom gradients, window drag isolation, traffic light insets) or platform-specific workarounds under the guise of "simplification" or "clean code".
  - **Strict Behavioral Invariance**: Refactoring must remain strictly internal and behavior-preserving. If a logic branch or check exists to handle an edge case or platform nuance, keep it intact.
- **Lazy Senior Dev Mode (YAGNI)**: Always prefer Apple native platform APIs and Swift standard library over custom helper classes or third-party abstractions.
- **No KVC / Selector Reflection**:
  - Do NOT use Objective-C runtime reflection (`value(forKey:)`, `setValue(_:forKey:)`, `NSSelectorFromString`, `performSelector`) to access SDK properties or private methods.
  - Always prefer native Swift platform APIs (e.g. `window.performDrag(with:)`).
  - When accessing non-public SDK properties that exist at the C/ObjC layer (such as `auditToken` on `NSXPCConnection`), declare the interface category in the target's `Bridging-Header.h` so the Swift Clang Importer provides first-class, type-safe native Swift syntax with zero runtime reflection overhead.
- **CryptoKit**: Use `CryptoKit` (`P256.Signing`) for all EC key generation, ECDSA signing, and signature verification. Avoid legacy C-style `SecKey` / `Security` framework APIs.
- **API Precedence: Public First, Public API + Private ID, Strict Private API Ban**:
  - **Tier 1 (Public First - Mandatory Default)**: ALWAYS prioritize officially documented, public Apple platform APIs, SDK frameworks, and standard libraries (Swift Standard Library, SwiftUI, AppKit, Endpoint Security, CryptoKit, POSIX Libsystem).
  - **Tier 2 (Fallback: Public API + Undocumented/Private ID via Bridging Header)**: When Apple provides NO public API or event for a required system behavior (e.g. detecting active incoming calls, clamshell/display states, hardware power transitions):
    - ONLY use **Public C/Darwin APIs** (such as `<notify.h>`) declared in `Bridging-Header.h` parameterized with **Undocumented/Private Identifiers or State Values** discovered via reverse engineering (e.g. `"com.apple.sharing.activity-level-changed"` with state `14`).
    - The Swift Clang Importer automatically bridges these C declarations into first-class, type-safe native Swift syntax with zero runtime overhead.
    - Because the linked binary symbols are 100% public, this cleanly passes Apple Gatekeeper, automated Notarization scanners, and avoids sandbox entitlement drops (`NSCocoaErrorDomain Code=4097`).
  - **Tier 3 (Absolute Ban: Zero Private APIs)**: MUST NEVER use Private APIs:
    - DO NOT link against Private Frameworks (`CoreDuetContext`, `TelephonyUtilities`).
    - DO NOT use dynamic linking (`dlopen`, `dlsym`) to invoke private symbols.
    - DO NOT use Objective-C runtime reflection (`NSSelectorFromString`, `performSelector:`, `value(forKey:)`) to invoke private classes or methods.
    - Private APIs risk immediate sandbox termination, XPC connection invalidation (`NSCocoaErrorDomain Code=4097`), breaking changes across minor OS updates, and Gatekeeper/Notarization rejection.
- **App Icon Caching**: Always load app icons via `AppIconProvider.shared.icon(forPath:size:)` to leverage the in-memory `NSCache` system and avoid redundant disk read operations.

---

## Performance & Simplicity Rules

- **Swift Concurrency over GCD**:
  - Prefer modern `async/await` and `Task` over legacy `DispatchQueue.global().async` / `DispatchQueue.main.async`.
  - Always execute UI updates on `@MainActor` and compute heavy operations (cdhash extraction, file I/O) in background Tasks or `nonisolated static` helpers.
- **Combine & Filter Debouncing**:
  - Use `RunLoop.main` or `DispatchQueue.main` for Combine search filter `.debounce` pipelines to keep publisher streams isolated to the main actor without cross-thread hops.
  - Use standardized `String.normalized` trimming whitespaces/newlines for instant, zero-alloc search matching.
- **Strict Resource & Observer Cleanup**:
  - All `NotificationCenter` observers, `NSMetadataQuery` instances, and Carbon Event Handlers (`InstallEventHandler`) MUST be explicitly torn down in `deinit`.
  - Clear `invalidationHandler` and `interruptionHandler` on `NSXPCConnection` before invoking `.invalidate()` to prevent recursive invalidation loops.
- **Native Platform First & YAGNI**:
  - Always prefer Apple native APIs (e.g. `NSAlert.beginSheetModal`, Swift Standard Library `UInt8.random`, `CryptoKit`) over custom wrapper abstractions.
  - Keep codebase simple and lean. Avoid speculative features or unnecessary protocol indirections unless required for previews/tests.
