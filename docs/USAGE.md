# AppLocker User Guide

[ English | [Tiếng Việt](USAGE-vi.md) ]

AppLocker is a native macOS security utility that intercepts application launches and requires user authentication (Touch ID or System Password) before execution.

---

## System Requirements

- **macOS Version**: macOS 13 (Ventura) or later.
- **System Integrity Protection (SIP)**: Must be **disabled** to allow the Endpoint Security (ES) system extension to load and intercept process launches at kernel level.

---

## Initial Setup

### 1. Disable System Integrity Protection (SIP)
1. Turn off your Mac.
2. Boot into Recovery Mode:
   - **Apple Silicon (M1/M2/M3/M4)**: Press and hold the **Power button** until "Loading startup options" appears, then select **Options > Continue**.
   - **Intel Macs**: Hold `Cmd + R` immediately after powering on until the Apple logo appears.
3. In the top menu bar, open **Utilities > Terminal**.
4. Run the command:
   ```bash
   csrutil disable
   ```
5. Restart your Mac.

### 2. Enable System Extension
1. Drag `AppLocker.app` into your `/Applications` directory and launch it.
2. When prompted, allow the system extension installation.
3. Open **System Settings > Privacy & Security**.
4. Scroll down to the **Security** section and click **Allow** next to the prompt for software from developer *"Tran Phuong"*.

---

## Managing Locked Applications

Access the management window at any time by clicking the **AppLocker lock icon (`🔒`)** in your macOS menu bar and choosing **Manage the application list…** (or press `Cmd + Shift + L`).  
*Note: Opening the management window requires authentication.*

### Locking an Application
1. In the AppLocker main window, click the **`+` (Plus)** button in the header.
2. Select applications from the **Applications** or **System Applications** list.
3. Alternatively, click **Select Other Applications…** to browse for any custom `.app` bundle using Finder.
4. Click **Lock** to enforce protection.

### Unlocking an Application
1. Click the **`-` (Minus / Trash)** icon next to the app in your locked list.
2. The app is placed into the **Unlock Waiting List**.
3. Click the notification bar at the bottom (*"Waiting to unlock N application(s)..."*).
4. Review the queue and click **Unlock** to confirm removal.

---

## Launching a Locked Application

1. Open any locked application as normal (via Finder, Dock, Spotlight, or Launchpad).
2. AppLocker will intercept the launch before the process starts.
3. An authentication dialog will appear asking for **Touch ID** or your **macOS User Password**.
4. Upon successful authentication, the application will launch immediately. If authentication fails or is cancelled, the launch is aborted.

---

## Menu Bar Controls & Shortcuts

| Shortcut | Menu Action | Description |
| :--- | :--- | :--- |
| `Cmd + Shift + L` | **Manage the application list…** | Opens the app list manager (requires authentication). |
| `Cmd + ,` | **Settings…** | Configure automatic software update checks, downloads, and channels (Stable / Beta). |
| — | **Check for Updates…** | Manually check for software updates. |
| — | **About AppLocker** | View current app version and developer information. |
| — | **Uninstall AppLocker…** | Deauthorizes the system extension, removes background services, and uninstalls AppLocker cleanly. |
| `Option` (Hold) | **Reset AppLocker…** | Reset all settings and clear the locked applications list (requires authentication). |

---

## Uninstallation

To cleanly remove AppLocker, its system extension, background agent, and settings:

### Recommended (Automatic Uninstall)
1. Make sure all locked applications have been unlocked.
2. Click the **AppLocker lock icon (`🔒`)** in your macOS menu bar.
3. Select **Uninstall AppLocker…**.
4. Confirm the uninstallation prompt. AppLocker will automatically:
   - Deauthorize and unload the Endpoint Security system extension.
   - Stop and remove the background agent (`launchd`).
   - Clean up application configuration files.
   - Move `AppLocker.app` to Trash.
5. Restart your Mac when prompted to finalize system cleanup.

### Manual Cleanup
If you have already deleted `AppLocker.app` manually:
1. Delete residual configuration and launch agent files:
   ```bash
   rm -rf ~/Library/Application\ Support/AppLocker
   rm -rf ~/Library/LaunchAgents/com.TranPhuong319.AppLocker.agent.plist
   ```
2. (Optional) Re-enable System Integrity Protection (SIP) if you no longer require process interception:
   - Boot into **Recovery Mode** -> **Utilities > Terminal**.
   - Run `csrutil enable` and restart your Mac.

---

## Troubleshooting & Reset

### System Extension Blocked
- Ensure SIP is disabled (`csrutil status` in Terminal should output `System Integrity Protection status: disabled.`).
- Go to **System Settings > Privacy & Security** and allow the system extension under Security.

### Reset Configuration
If you need to restore AppLocker to default settings:
1. Hold `Option` key while opening the menu bar icon `🔒`.
2. Click **Reset AppLocker…** and authenticate.
3. Or manually delete the configuration file:
   ```bash
   rm -rf ~/Library/Application\ Support/AppLocker
   ```
