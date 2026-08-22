# Feature Specification: Robust Uninstall and Reset Workflow

**Feature Branch**: `003-fix-uninstall-reset`

**Created**: 2026-08-22

**Status**: Draft

**Input**: User description: "Lập cho tôi plan để sửa logic Uninstall và logic Reset /speckit-specify /ponytail"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Secure & Complete Application Uninstallation (Priority: P1)

As an AppLocker user or system administrator, I want the Uninstall operation to prompt for confirmation with a clear description, authenticate the administrator via macOS native System Extension deactivation request, unregister the background LaunchAgent, delete all AppLocker configuration directories (`/Users/Shared/AppLocker`), and cleanly move the application bundle to the Trash without forcing an abrupt Mac reboot, so that my system is cleanly restored to its pre-installation state.

**Why this priority**: Core security and usability. Uninstallation leverages macOS native admin authentication for extension deactivation, removes all user configs and background services, and avoids interrupting the user's ongoing computer session with an unnecessary reboot.

**Independent Test**:
- Can be tested by selecting "Uninstall AppLocker…" from the menu bar, confirming the action, verifying macOS prompts for administrator authentication to deactivate the system extension, and verifying that the System Extension is deactivated, LaunchAgent removed, `/Users/Shared/AppLocker` deleted, and `AppLocker.app` recycled to Trash with the app terminating cleanly.

**Acceptance Scenarios**:
1. **Given** AppLocker is running, **When** the user clicks "Uninstall AppLocker…", **Then** the app displays a confirmation alert: "You are about to uninstall AppLocker. This action will delete application locking preferences for all users on this Mac.\n\nDo you want to continue?".
2. **Given** the user confirms uninstallation in the alert, **When** the confirmation is accepted, **Then** `ExtensionInstaller` initiates extension deactivation, triggering macOS native administrator authentication prompt.
3. **Given** administrator authorization succeeds, **When** uninstallation proceeds, **Then** `com.TranPhuong319.AppLocker.ESExtension` is deactivated, `manageAgent` unregisters the background agent, `removeConfig(purgeAll: true)` deletes the entire `/Users/Shared/AppLocker` directory and `UserDefaults`, `selfRemoveApp` moves the app to Trash, and the app terminates cleanly without triggering an OS reboot.
4. **Given** authorization fails or is cancelled, **When** prompted by macOS, **Then** the uninstallation process is aborted immediately without modifying configuration or removing files.

---

### User Story 2 - Biometric-Protected & Instant Configuration Reset (Priority: P1)

As an AppLocker user, I want the Reset AppLocker operation to authenticate the device owner, purge all locked application rules and settings for the current user (`/Users/Shared/AppLocker/<UID>`), reset all user defaults for the current user, and cleanly relaunch the application into a fresh default state, so that I can troubleshoot or start over without manual file manipulation.

**Why this priority**: Essential troubleshooting workflow. Resetting allows users to clear bad states or start fresh with a single authenticated action.

**Independent Test**:
- Can be tested by holding Option in the menu bar, clicking "Reset AppLocker…", authenticating via Touch ID / Password, and observing that current user configuration is erased, `UserDefaults` reset, and AppLocker relaunches with an empty application lock list.

**Acceptance Scenarios**:
1. **Given** locked applications are configured, **When** the user holds `Option` and clicks "Reset AppLocker…" in the menu bar, **Then** a confirmation dialog is presented.
2. **Given** the user confirms reset, **When** the prompt is approved, **Then** biometric/password authentication is requested via `AuthenticationManager.authenticate`.
3. **Given** authentication succeeds, **When** reset executes, **Then** the user's configuration directory (`/Users/Shared/AppLocker/<UID>/`) and `UserDefaults` are removed, and the application relaunches cleanly.

---

### User Story 3 - Graceful Fallback & Error Handling during Uninstall/Reset (Priority: P2)

As a macOS user encountering permissions or extension deactivation failures during Uninstall or Reset, I want descriptive, non-blocking error feedback so that I understand exactly what failed.

**Why this priority**: Reliability. Prevents silent partial state or zombie background extensions if deactivation encounters macOS system errors.

**Independent Test**:
- Can be tested by simulating a failed extension deactivation or permission error during trash recycling, verifying that an informative alert is shown and error logs are recorded.

**Acceptance Scenarios**:
1. **Given** extension deactivation fails (e.g. system extension manager rejection), **When** uninstallation is attempted, **Then** AppLocker halts the uninstallation, displays an error alert with the localized description, and leaves the application bundle and configs intact.
2. **Given** moving the app bundle to Trash fails due to file permissions, **When** file recycling returns an error, **Then** AppLocker notifies the user to manually remove `/Applications/AppLocker.app`.

---

### Edge Cases

- **Multiple User Configs on Uninstall**: When uninstallation is performed, the entire `/Users/Shared/AppLocker/` directory is deleted.
- **Single User Reset vs Global Reset**: When Reset is performed, only `/Users/Shared/AppLocker/<UID>/` is removed so other macOS user accounts on the same machine retain their rules.
- **Single Instance Handover on Reset**: Relaunch during Reset uses `-waitForPID` coordination to ensure the exiting process terminates before the new instance initializes.

---

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST show a clear confirmation alert on Uninstall stating: `"You are about to uninstall AppLocker. This action will delete application locking preferences for all users on this Mac.\n\nDo you want to continue?"`.
- **FR-002**: System MUST require local user authentication via `AuthenticationManager.authenticate` before executing `performReset()`.
- **FR-003**: System MUST rely on macOS native administrator authorization modal triggered by `OSSystemExtensionRequest.deactivationRequest` when deactivating `ESExtension` during `performUninstall()`.
- **FR-004**: On successful uninstallation, system MUST:
  1. Deactivate `ESExtension` via `ExtensionInstaller.shared.uninstall`.
  2. Disconnect XPC communication (`ESXPCClient.shared.disconnect()`).
  3. Unregister the LaunchAgent (`manageAgent(plistName:action:.uninstall)`).
  4. Delete the persistent domain in `UserDefaults`.
  5. Delete the entire shared base directory `/Users/Shared/AppLocker`.
  6. Recycle the application bundle (`AppLocker.app`) to Trash via `NSWorkspace.shared.recycle`.
  7. Terminate the application cleanly without invoking forced system reboot scripts (`loginwindow` AppleScript).
- **FR-005**: On successful reset, system MUST:
  1. Delete the current user's persistent domain in `UserDefaults`.
  2. Delete `/Users/Shared/AppLocker/<UID>/` directory.
  3. Relaunch the application cleanly with single-instance handover (`restartApp()`).
- **FR-006**: If system extension deactivation fails during uninstall, system MUST abort further file deletion, log the error, and display an informative alert.

---

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Complete removal of all AppLocker artifacts (`/Users/Shared/AppLocker`, `UserDefaults`, LaunchAgent) upon successful uninstallation.
- **SC-002**: Zero forced system reboots during uninstallation; user session remains uninterrupted.
- **SC-003**: Application reset completes and relaunches a fresh instance in $\le 2$ seconds.
- **SC-004**: All SwiftLint rules pass with 0 errors and 0 warnings on modified files.
