# AppLocker User Guide

Welcome to AppLocker! This guide will help you understand how to use the application effectively to secure your macOS applications.

## Table of Contents
1. [Installation](#installation)
2. [First Launch & Modes](#first-launch--modes)
3. [Managing Locked Apps](#managing-locked-apps)
4. [Authentication](#authentication)
5. [Troubleshooting](#troubleshooting)

## Installation

1. Download the latest release from the [Releases Page](https://github.com/TranPhuong319/AppLocker/releases).
2. Drag and drop `AppLocker.app` into your `/Applications` folder.
3. Launch the application.

## First Launch & Modes

AppLocker operates in two main modes. The choice depends on your security needs and system configuration.

### 1. Endpoint Security (ES) Mode (Recommended)
This mode uses Apple's Endpoint Security framework for robust and secure application blocking.

- **Requirement**: You must disable **System Integrity Protection (SIP)** to load the system extension.
- **Setup**:
    1. Disable SIP (Boot into Recovery Mode > Terminal > `csrutil disable` > Restart).
    2. Open AppLocker.
    3. Click "Install System Extension" when prompted.
    4. Allow the extension in **System Settings > Privacy & Security**.

### 2. Launcher Mode
This is a simpler mode that doesn't require disabling SIP but provides less robust protection (it relies on wrapping the app launch).

- **Setup**:
    1. Open AppLocker.
    2. Choose "Launcher Mode" if prompted or configured.
    3. You may need to provide administrator privileges to set up the helper tools.

## Managing Locked Apps

### Adding an App
1. Open the AppLocker main window.
2. Click the **"+"** (Plus) button at the top-left or bottom-left of the window.
3. Select the application you want to lock from the file picker.
4. The app will appear in the list.

### Removing an App
1. Select the app you want to remove from the list.
2. Click the **"-"** (Minus) button or press `Delete` on your keyboard.

## Authentication

When you try to open a locked application:
1. The application launch will be intercepted.
2. An AppLocker authentication window will appear.
3. Enter your password (or use Touch ID if configured).
4. If successful, the application will launch.

## Troubleshooting

### "System Extension Blocked"
If you see this message, go to **System Settings > Privacy & Security** and look for a message about software from "Tran Phuong" being blocked. Click **Allow**.

### App not launching after password
- Ensure the password is correct.
- Check if AppLocker is running in the menu bar.
- If using ES mode, verify that the extension is active (green indicator in the main app).

### Resetting AppLocker
If you encounter persistent issues, you can reset the configuration:
1. Quit AppLocker.
2. Delete `~/Library/Application Support/AppLocker`.
3. Delete `~/Library/Preferences/com.fpt.AppLocker.plist`.
