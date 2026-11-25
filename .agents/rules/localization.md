# Localization & Communication Style Guidelines

## Localization & String Catalog Guidelines

- **English Base Keys & Static String Literals**:
  - Write base localization keys in **English** using static String literals (e.g. `case .general: return "General"` in enum `switch self` statements; dynamic variables in `LocalizedStringKey` / `String(localized:)` are banned via SwiftLint).
  - Strings inside `#if DEBUG` blocks may be marked `"extractionState": "stale"` by Release extraction; remove `"stale"` when keeping `#if DEBUG` strings intentionally (unintentional new `stale` entries in `.xcstrings` are gated at `Stop`).

---

## Language & Communication Style Guidelines

- **Primary Language**: Always communicate, explain, and interact with the user in **Vietnamese (Tiếng Việt)**.
- **Technical Terms**: Keep industry-standard, framework, and programming terminology in **English (Thuật ngữ Tiếng Anh)** (e.g., *deployment target, view modifier, content transition, background tasks, thread isolation, dependency injection, runtime checks, audit token, mutual authentication*).
