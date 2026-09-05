# AppLocker User Guide

[ English | [Tiếng Việt](USAGE-vi.md) ]

AppLocker is a native macOS security utility that intercepts application launches and requires user authentication (Touch ID, Apple Watch, or System Password) before execution.

---

## 💻 System Requirements

- **macOS Version**: macOS 14.0 (Sonoma) or later.
- **Hardware Architecture**: Apple Silicon (M1/M2/M3/M4) and Intel (x86_64).
- **System Integrity Protection (SIP)**: Must be **disabled** to allow the Endpoint Security (ES) system extension to load without a paid Apple Developer provisioning profile.

---

## 🛠️ Initial Setup

### 1. Disable System Integrity Protection (SIP)
1. Turn off your Mac completely.
2. Boot into **Recovery Mode**:
   - **Apple Silicon (M1/M2/M3/M4)**: Press and hold the **Power button** until *"Loading startup options"* appears $\rightarrow$ select **Options > Continue** $\rightarrow$ Go to the top menu **Utilities > Startup Security Utility** $\rightarrow$ Select your drive $\rightarrow$ Choose **Reduced Security**.
   - **Intel Macs**: Hold `⌘ + R` immediately after powering on until the Apple logo appears.
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

## 📋 Managing Locked Applications

Access the management window at any time by clicking the **AppLocker lock icon (`🔒`)** in your macOS menu bar and choosing **Manage the application list…** (or press `⌘ + ⇧ + L`).  
*(Note: Opening the management window requires authentication).*

<div align="center">
  <img src="images/screenshots/screenshot-main.png" width="80%" alt="Main Management Dashboard" />
  <p><i>Main locked applications management window</i></p>
</div>

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

## 🚀 Launching a Locked Application

1. Open any locked application as normal (via Finder, Dock, Spotlight, or Launchpad).
2. AppLocker will intercept and suspend the launch at the Kernel level before any UI is rendered.
3. An authentication dialog will appear asking for **Touch ID**, **Apple Watch**, or your **macOS User Password**:
   - **Single-App Authentication**: When launching an individual locked application.
   - **Batch Authentication**: When opening multiple locked applications at once, AppLocker groups them automatically for a single-pass approval.
4. Upon successful authentication, the process is resumed (`SIGCONT`). If authentication fails or is cancelled, the process is safely terminated (`SIGKILL`).

| Single-App Authentication | Batch Authentication |
| :---: | :---: |
| <img src="images/screenshots/screenshot-auth.png" width="380" alt="Single-App Authentication Dialog" /> | <img src="images/screenshots/screenshot-mutiple-auth.png" width="380" alt="Batch Authentication Dialog" /> |

---

## ⚡ Menu Bar Controls & Shortcuts

<div align="center">
  <img src="images/screenshots/screenshot-menubar.png" width="50%" alt="Menu Bar Access" />
  <p><i>Quick actions from the macOS Menu Bar</i></p>
</div>

| Shortcut | Menu Action | Description |
| :--- | :--- | :--- |
| `⌘ + ⇧ + L` | **Manage the application list…** | Opens the app list manager (requires authentication). |
| `⌘ + ,` | **Settings…** | Configure automatic software update checks, downloads, and channels (Stable / Beta). |
| — | **Check for Updates…** | Manually check for software updates. |
| — | **About AppLocker** | View current app version and developer information. |
| — | **Uninstall AppLocker…** | Deauthorizes the system extension, removes background services, and uninstalls AppLocker cleanly. |
| `⌥` (Hold) | **Reset AppLocker…** | Reset all settings and clear the locked applications list (requires authentication). |

---

## 🗑️ Uninstallation

To cleanly remove AppLocker, its system extension, background agent, and settings:

### Recommended (Automatic Uninstall)
1. Click the **AppLocker lock icon (`🔒`)** in your macOS menu bar.
2. Select **Uninstall AppLocker…**.
3. Confirm the uninstallation prompt. AppLocker will automatically:
   - Deauthorize and unload the Endpoint Security system extension (prompts for admin authorization).
   - Stop and remove the background agent (`launchd`).
   - Clean up application configuration files (`/Users/Shared/AppLocker`).
   - Move `AppLocker.app` to Trash.

### Manual Cleanup
If you have already deleted `AppLocker.app` manually:
1. Delete residual configuration and launch agent files:
   ```bash
   sudo rm -rf /Users/Shared/AppLocker
   rm -rf ~/Library/LaunchAgents/com.TranPhuong319.AppLocker.agent.plist
   ```
2. (Optional) Re-enable System Integrity Protection (SIP) if you no longer require process interception:
   - Boot into **Recovery Mode** -> **Utilities > Terminal**.
   - Run `csrutil enable` and restart your Mac.

---

## 🔧 Troubleshooting & Reset

### System Extension Blocked
- Ensure SIP is disabled (`csrutil status` in Terminal should output `System Integrity Protection status: disabled.`).
- Go to **System Settings > Privacy & Security** and allow the system extension under Security.

### Reset Configuration
> [!WARNING]
> Resetting AppLocker will permanently erase the locked applications list and shared configuration for **all users** on this Mac.

If you need to restore AppLocker to default settings:
1. Hold `⌥` key while opening the menu bar icon `🔒`.
2. Click **Reset AppLocker…** and authenticate.
3. Or manually delete the shared configuration file:
   ```bash
   sudo rm -rf /Users/Shared/AppLocker
   ```
