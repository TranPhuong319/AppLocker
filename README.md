# 🔐 AppLocker – macOS Application Locker

**AppLocker** là một công cụ bảo mật dành cho macOS giúp khóa các ứng dụng bất kỳ bằng cơ chế nguỵ trang và yêu cầu xác thực người dùng trước khi truy cập.

Dự án này bao gồm:

- `AppLocker.app`: Ứng dụng chính chạy ở menu bar, quản lý ứng dụng bị khóa.
- `AppLockerHelper`: Privileged helper (chạy dưới quyền `root`) dùng để xử lý việc kiểm soát quyền truy cập ứng dụng.
- `com.TranPhuong319.AppLockerHelper.plist`: LaunchDaemon để khởi chạy helper khi boot máy.
- `buildpkg`: Script dùng `pkgbuild` để tạo gói cài `.pkg`.
- `postinstall`: Script hậu cài đặt để cấp quyền và đăng ký helper.

---

## 📦 Tải bản phát hành (Releases)

Bạn có thể tải các bản phát hành `.pkg` cài đặt sẵn từ mục [Releases](https://github.com/TranPhuong319/AppLocker/releases) trên GitHub.

File `.pkg` bao gồm:
- `AppLocker.app` đã đóng gói
- `AppLockerHelper` helper tool đã đăng ký launchd
- Script hậu cài đặt để tự động cấu hình

> ⚠️ Sau khi tải về, macOS có thể yêu cầu cấp quyền chạy (do app không ký code): chuột phải → Open.

## ✅ Yêu cầu hệ thống

- macOS Ventura trở lên
- Terminal với quyền `admin`
- Xcode command line tools (`pkgbuild`, `installer`, etc.)

---

## ⚙️ Cách build file `.pkg`

### 1. Dọn dẹp file ẩn `.DS_Store` (nếu có):

```bash
find AppLocker_Pkg/ -name .DS_Store -delete
```

### 2. Đảm bảo quyền file chính xác:

```bash
chmod -R 755 AppLocker_Pkg/root/Applications/AppLocker.app
chown -R root:wheel AppLocker_Pkg/root/Applications/AppLocker.app

chmod 755 AppLocker_Pkg/root/Library/PrivilegedHelperTools/AppLockerHelper
chown root:wheel AppLocker_Pkg/root/Library/PrivilegedHelperTools/AppLockerHelper

chmod 644 AppLocker_Pkg/root/Library/LaunchDaemons/com.TranPhuong319.AppLockerHelper.plist
chown root:wheel AppLocker_Pkg/root/Library/LaunchDaemons/com.TranPhuong319.AppLockerHelper.plist

chmod +x AppLocker_Pkg/scripts/postinstall
```

### 3. Build `.pkg`:

```bash
./buildpkg
```

> Nếu lỗi, kiểm tra script `buildpkg` đã có `#!/bin/bash` và có quyền thực thi.

---

## 📦 Cài đặt AppLocker

Sau khi đã có file `AppLocker.pkg`, bạn cài đặt bằng:

```bash
sudo installer -pkg AppLocker.pkg -target /
```

Sau cài đặt, các thành phần sẽ nằm ở:

| Thành phần | Vị trí |
|------------|--------|
| App | `/Applications/AppLocker.app` |
| Helper | `/Library/PrivilegedHelperTools/AppLockerHelper` |
| LaunchDaemon | `/Library/LaunchDaemons/com.TranPhuong319.AppLockerHelper.plist` |

Helper sẽ được đăng ký và tự động chạy bằng launchd.

---

## 📄 Script `postinstall`

Script `postinstall` sẽ:

- Cấp quyền thực thi cho helper
- Gán owner là `root:wheel`
- Đăng ký helper với launchd bằng `launchctl bootout` + `launchctl bootstrap`

---

## 🧪 Ghi log (Comming Soon)

Helper ghi log hoạt động (copy icon, xác thực, lỗi) vào:

```
/tmp/AppLockerHelper.log
```

Bạn có thể xem bằng:

```bash
tail -f /tmp/AppLockerHelper.log
```

---

## ❌ Gỡ cài đặt hoàn toàn

```bash
sudo launchctl bootout system /Library/LaunchDaemons/com.TranPhuong319.AppLockerHelper.plist
sudo rm /Library/LaunchDaemons/com.TranPhuong319.AppLockerHelper.plist
sudo rm /Library/PrivilegedHelperTools/AppLockerHelper
sudo rm -rf /Applications/AppLocker.app
sudo rm -f /tmp/AppLockerHelper.log
```

---

## ✏️ Ghi chú thêm

- Nếu icon trong `CFBundleIconFile` chứa `.icns`, AppLocker sẽ tự động loại `.icns` để tránh lỗi `icon.icns.icns`.
- App hỗ trợ xác thực bằng mật khẩu hệ thống hoặc Touch ID.

---

## 🧑‍💻 Tác giả

**Trần Phương**  
GitHub: [@TranPhuong319](https://github.com)
