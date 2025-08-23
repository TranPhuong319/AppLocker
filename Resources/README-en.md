# 🔐 AppLocker – macOS Application Locker

**AppLocker** is a macOS security tool that lets you lock any application with a disguise mechanism and require user authentication before access.  

This project includes:

- `AppLocker.app`: The main menu bar application that manages locked apps.  
- `AppLockerHelper`: A privileged helper tool (runs as `root`) that handles access control.  
- `com.TranPhuong319.AppLockerHelper.plist`: A LaunchDaemon to start the helper at boot.  

---

## 📦 Releases

You can download prebuilt `.pkg` installation packages from the [Releases](https://github.com/TranPhuong319/AppLocker/releases) section on GitHub.  

The `.pkg` file includes:  
- Packaged `AppLocker.app`  
- `AppLockerHelper` helper tool registered with launchd  
- Post-installation script for automatic configuration  

> ⚠️ After downloading, macOS may require you to allow the app to run (since the app is unsigned): Right click → Open.  

---

## ✅ System Requirements

- macOS Ventura or later  

---

## ⚙️ Build the `.pkg` File

### 1. Download and install [Packages](http://s.sudre.free.fr/files/Packages_1211_dev.dmg)  

### 2. Open the `AppLocker.pkgproj` file  

### 3. Build the package  
- Go to **Build → Build** or press `⌘ + B`  
- After building, the `.pkg` file will be located in `Product/AppLocker.pkg`  

<img width="881" height="369" alt="Screenshot 2025-08-23 at 08 04 21" src="https://github.com/user-attachments/assets/5f89ce9a-7b2a-4794-baa1-bca3caa10f09" />

---

## 📦 Install AppLocker

Once you have the `AppLocker.pkg` file, install it by running:

```bash
sudo installer -pkg AppLocker.pkg -target /
```

Or simply open the installer file. At the `Installation Type` step, select ***Install AppLocker*** (default option).  
Click **Continue**, enter your administrator password, and the software will be installed.  

<img width="622" height="448" alt="image" src="https://github.com/user-attachments/assets/86195b76-cffa-42b3-9566-0295d145b8a1" />

After installation, components will be located at:

| Component   | Path |
|-------------|------|
| App         | `/Applications/AppLocker.app` |
| Helper      | `/Library/PrivilegedHelperTools/AppLockerHelper` |
| LaunchDaemon| `/Library/LaunchDaemons/com.TranPhuong319.AppLockerHelper.plist` |

The helper will be registered and automatically started by **launchd**.  

---

## 🧪 Logs

You can view logs using **Console.app**.  

---

## ❌ Complete Uninstallation

- Run the `AppLocker.pkg` file again  
- At the `Installation Type` step, uncheck **Install AppLocker**  
- Click **Continue**, enter your administrator password  

<img width="622" height="447" alt="image" src="https://github.com/user-attachments/assets/f56e2ff7-bbad-4a19-8fcc-155400709e87" />

The software will be removed.  

> ⚠️ Make sure all applications are **unlocked** before uninstalling.  

---

## 🧑‍💻 Author

**Trần Phương**  
GitHub: [@TranPhuong319](https://github.com/TranPhuong319)  
