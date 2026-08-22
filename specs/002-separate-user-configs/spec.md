# Feature Specification: Per-User Configuration File Separation

**Feature Branch**: `002-separate-user-configs`

**Created**: 2026-08-22

**Status**: Draft

**Input**: User description: "Thay đổi tính năng: Tách các user trong dict thành file riêng biệt: Từ /Users/Shared/AppLocker/config.plist thành /Users/Shared/AppLocker/(&UID)/config.plist. ES khi init sẽ nạp toàn bộ file config tương ứng với mỗi uid. /ponytail"

## Clarifications

### Session 2026-08-22

- Q: How should AppLocker and ESExtension handle the legacy shared file (`/Users/Shared/AppLocker/config.plist`) after its data has been migrated into per-user directories? → A: Migrate all $N$ UIDs from the legacy file into their respective `/Users/Shared/AppLocker/<UID>/config.plist` files at once, then delete the legacy `/Users/Shared/AppLocker/config.plist` file to eliminate dual-source-of-truth conflicts.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Isolated Per-User Configuration Storage (Priority: P1)

As a macOS user on a multi-user or single-user Mac, I want AppLocker to persist my locked application rules and settings into my own user directory (`/Users/Shared/AppLocker/<UID>/config.plist`) so that my configuration is completely isolated from other users, eliminating write collisions and race conditions.

**Why this priority**: Core architectural change. Replaces single shared dictionary file with per-user configuration files, resolving concurrent write conflicts across macOS user accounts.

**Independent Test**:
- Can be tested by launching AppLocker under a specific macOS user account (UID 501), modifying locked apps or toggle state, and verifying that rules are saved directly to `/Users/Shared/AppLocker/501/config.plist` without requiring a global UID dictionary in a single file.

**Acceptance Scenarios**:
1. **Given** an active macOS user session with UID `501`, **When** the user adds or modifies locked apps in AppLocker, **Then** AppLocker saves the user's `UserConfig` directly to `/Users/Shared/AppLocker/501/config.plist`.
2. **Given** an active macOS user session with UID `502`, **When** user 502 configures locked apps, **Then** `/Users/Shared/AppLocker/502/config.plist` is created/updated without altering or locking user 501's configuration.

---

### User Story 2 - Comprehensive Multi-User Config Ingestion in ESExtension (Priority: P1)

As a security daemon (`ESExtension`), I want to discover and load configuration files across all existing UID subdirectories (`/Users/Shared/AppLocker/<UID>/config.plist`) at startup and on runtime updates, so that application locking rules for all active users are enforced without missing any user configuration.

**Why this priority**: Critical security enforcement. The privileged Endpoint Security extension must aggregate rules across all user accounts on the machine to intercept executions accurately per UID.

**Independent Test**:
- Can be tested by placing valid configuration files for multiple UIDs (e.g. 501 and 502) in `/Users/Shared/AppLocker/<UID>/config.plist` and restarting ESExtension or triggering a reload, then verifying that both UID rules are active in memory.

**Acceptance Scenarios**:
1. **Given** multiple user configuration folders (e.g. `501/config.plist`, `502/config.plist`) exist under `/Users/Shared/AppLocker/`, **When** ESExtension initializes or receives a reload signal, **Then** ESExtension scans all numeric subdirectories and loads the respective rules mapped to each UID.
2. **Given** a user updates their configuration while ESExtension is running, **When** the file modification is saved, **Then** ESExtension detects the change and refreshes the in-memory rules for the modified UID.

---

### User Story 3 - Full Atomic Migration for All UIDs & Legacy Cleanup (Priority: P2)

As an existing AppLocker user or system administrator updating from a previous version, I want all existing user configurations stored in the legacy `/Users/Shared/AppLocker/config.plist` to be migrated to their respective UID directories (`/Users/Shared/AppLocker/<UID>/config.plist`) and the legacy file to be removed, so that no user loses settings and no stale configuration file remains.

**Why this priority**: Prevents configuration loss across all accounts on the Mac during upgrade and avoids split-brain file reads.

**Independent Test**:
- Can be tested by creating a legacy `/Users/Shared/AppLocker/config.plist` containing rules for multiple UIDs (e.g., 501 and 502), running migration, and verifying that both `/Users/Shared/AppLocker/501/config.plist` and `/Users/Shared/AppLocker/502/config.plist` are created while `/Users/Shared/AppLocker/config.plist` is deleted.

**Acceptance Scenarios**:
1. **Given** a legacy `/Users/Shared/AppLocker/config.plist` exists with configurations for $N$ UIDs, **When** migration is triggered, **Then** $N$ separate files (`<UID>/config.plist`) are created containing their respective `UserConfig` data.
2. **Given** all $N$ per-user config files are successfully written to disk, **When** migration concludes, **Then** the legacy file `/Users/Shared/AppLocker/config.plist` is deleted.

---

### User Story 4 - File Tamper Protection & Security Path Monitoring (Priority: P2)

As a security system, I want tamper protection and file monitoring in ESExtension to cover the entire `/Users/Shared/AppLocker/` directory hierarchy, ensuring that unauthorized processes cannot modify or delete any user's configuration file.

**Why this priority**: Security integrity. Protects configuration files under subdirectories from being tampered with by unauthorized non-AppLocker processes.

**Independent Test**:
- Can be tested by attempting to modify or delete `/Users/Shared/AppLocker/501/config.plist` from a non-authorized process (e.g., Terminal command) and verifying that ESExtension intercepts and denies the operation.

**Acceptance Scenarios**:
1. **Given** an unauthorized process attempts to modify or delete `/Users/Shared/AppLocker/<UID>/config.plist`, **When** the file operation is evaluated by `ESEventAuthFile`, **Then** the operation is denied.
2. **Given** AppLocker with valid XPC authorization writes to `/Users/Shared/AppLocker/<UID>/config.plist`, **When** the write occurs, **Then** the operation is allowed and monitoring reflects the new rules immediately.

---

### Edge Cases

- **Non-numeric subdirectories**: If a non-numeric folder exists in `/Users/Shared/AppLocker/` (e.g. `.DS_Store`, `temp`, `backup`), ESExtension MUST ignore it safely without crashing or recording invalid UIDs.
- **Corrupted single-user config file**: If one user's `config.plist` is corrupted or unreadable, ESExtension MUST log an error for that UID and continue loading all other valid user configs without failure.
- **Disabled user state**: If a user's `UserConfig.isDisabled` is set to `true`, ESExtension MUST exclude that UID from active locking rules while preserving the file.
- **Concurrent user login/switch**: When macOS switches between fast user switching sessions, directory monitoring must keep all user configs synchronized in ESExtension.
- **Subdirectory directory permissions**: User subdirectories (`/Users/Shared/AppLocker/<UID>/`) and config files must have appropriate POSIX permissions (e.g., directory `0o755` or `0o777`, file `0o644` or `0o666`) to allow AppLocker under standard user UID to read/write while maintaining daemon readability.
- **Partial migration failure**: If writing any UID file fails during migration, the legacy file MUST NOT be deleted until all UID files are successfully persisted.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST store each user's configuration in a distinct file located at `/Users/Shared/AppLocker/<UID>/config.plist`, where `<UID>` is the integer user identifier of the macOS user.
- **FR-002**: AppLocker application MUST read and write exclusively to `/Users/Shared/AppLocker/<UID>/config.plist` for the currently logged-in user (`getuid()`).
- **FR-003**: The stored configuration format within `/Users/Shared/AppLocker/<UID>/config.plist` MUST be a single `UserConfig` object containing `isDisabled: Bool` and `apps: [LockedAppConfig]`, removing the global `[String: UserConfig]` dictionary wrapping.
- **FR-004**: ESExtension MUST scan the `/Users/Shared/AppLocker/` directory upon initialization and load all valid `UserConfig` instances found in numeric UID subdirectories.
- **FR-005**: ESExtension MUST maintain in-memory `lockedCDHashes: [uid_t: Set<String>]` and `lockedBundlePaths: [uid_t: Set<String>]` aggregated across all discovered UID config files.
- **FR-006**: ESExtension MUST monitor file system changes across `/Users/Shared/AppLocker/` and its subdirectories, reloading or updating the affected UID rules with debouncing ($\le 50$ms).
- **FR-007**: System MUST perform full migration from legacy `/Users/Shared/AppLocker/config.plist`: all $N$ user dictionaries present in the legacy file MUST be converted into separate `<UID>/config.plist` files, after which the legacy file MUST be deleted.
- **FR-008**: System tamper protection (`isInsideProtectedFolder`, `isProtectedConfigPath`, `isRenameDestinationProtected`) MUST protect all files and subdirectories under `/Users/Shared/AppLocker/`.
- **FR-009**: Endpoint Security muting and watch lists MUST cover the parent directory `/Users/Shared/AppLocker` to capture file modifications across all current and future UID subdirectories.

### Key Entities

- **UserConfig**: Root configuration object for a single user, containing `isDisabled: Bool` (flag indicating if protection is temporarily paused for this user) and `apps: [LockedAppConfig]` (array of locked applications with path, name, cdhash, and settings).
- **UID Directory**: A directory located at `/Users/Shared/AppLocker/<UID>/` where `<UID>` is the numeric representation of a macOS user ID (e.g. `501`, `502`).
- **PerUserConfigFile**: The property list binary file stored at `/Users/Shared/AppLocker/<UID>/config.plist`.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Zero file write conflicts or locks between different macOS user accounts configuring AppLocker concurrently.
- **SC-002**: 100% of valid UID configuration files present under `/Users/Shared/AppLocker/` are loaded by ESExtension at startup in $\le 50$ms.
- **SC-003**: Configuration changes made by any user account take effect in ESExtension within $\le 100$ms of saving.
- **SC-004**: 100% of UIDs in legacy configuration files are successfully migrated to individual files with zero data loss before the legacy file is deleted.
- **SC-005**: Unauthorized access or modification attempts to any `/Users/Shared/AppLocker/<UID>/config.plist` are blocked by Endpoint Security tamper protection.

## Assumptions

- Standard macOS user UIDs are positive integers (typically $\ge 501$ for regular users, $0$ for root).
- The root shared directory `/Users/Shared/AppLocker/` exists or is created with permissions allowing users to create their own `<UID>` directories.
- Each user account runs AppLocker under their own UID, and `getuid()` correctly identifies the user context.
- System Extension runs as root (`UID 0`) and has full read access to all subdirectories within `/Users/Shared/AppLocker/`.
