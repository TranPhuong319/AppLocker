# Localization & Communication Style Guidelines

## Localization & String Catalog Guidelines

- **English Base Keys & Static String Literals**:
  - Always write base localization keys in **English** using explicit, static String literals (e.g. `return "General"` instead of `LocalizedStringKey(rawValue)`).
  - Do NOT pass dynamic variables into `LocalizedStringKey(rawValue)` or `String(localized: variable)`. Xcode's static compiler extractor cannot trace dynamic variables and will mark string keys as `stale` in `Localizable.xcstrings`.
  - For enums requiring localized display names, use explicit `switch self` statements returning String literals (e.g. `case .general: return "General"`).
  - Strings wrapped inside conditional compilation blocks (e.g. `#if DEBUG`) might be marked as `stale` during standard Release builds by Xcode's static extractor. Remove `"extractionState": "stale"` if the string is intentionally kept for DEBUG builds.

---

## Language & Communication Style Guidelines

- **Primary Language**: Always communicate, explain, and interact with the user in **Vietnamese (Tiếng Việt)**.
- **Technical Terms**: Keep industry-standard, framework, and programming terminology in **English (Thuật ngữ Tiếng Anh)** (e.g., *deployment target, view modifier, content transition, background tasks, thread isolation, dependency injection, runtime checks, audit token, mutual authentication*).
