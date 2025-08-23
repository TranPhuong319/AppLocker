# 🔐 AppLocker – macOS Application Locker

**AppLocker** là một công cụ bảo mật dành cho macOS giúp khóa các ứng dụng bất kỳ bằng cơ chế nguỵ trang và yêu cầu xác thực người dùng trước khi truy cập.

Dự án này bao gồm:

- `AppLocker.app`: Ứng dụng chính chạy ở menu bar, quản lý ứng dụng bị khóa.
- `AppLockerHelper`: Privileged helper (chạy dưới quyền `root`) dùng để xử lý việc kiểm soát quyền truy cập ứng dụng.
- `com.TranPhuong319.AppLockerHelper.plist`: LaunchDaemon để khởi chạy helper khi boot máy.
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

---

## ⚙️ Build file `.pkg`

### 1. Tải và cài đặt phần mềm [Packages](http://s.sudre.free.fr/files/Packages_1211_dev.dmg)

### 2. Mở file AppLocker.pkgproj

### 3. Build phần mềm
- Chọn vào Build -> Build hoặc nhấn ⌘ + B
- Sau khi build xong, file pkg sẽ nằm ở `Product/AppLocker.pkg`

<img width="881" height="369" alt="Ảnh màn hình 2025-08-23 lúc 08 04 21" src="https://github.com/user-attachments/assets/5f89ce9a-7b2a-4794-baa1-bca3caa10f09" />

---

## 📦 Cài đặt AppLocker

Sau khi đã có file `AppLocker.pkg`, bạn cài đặt bằng:

```bash
sudo installer -pkg AppLocker.pkg -target /
```
Hoặc chạy tệp cài đặt. Đến bước `Loại cài đặt`, chọn vào ***Cài đặt AppLocker*** (Mặc định đã được chọn)
Nhấn Tiếp tục, nhập mật khẩu quản trị viên. Phần mềm sẽ được cài đặt

<img width="624" height="447" alt="image" src="https://github.com/user-attachments/assets/092b0561-2db5-4fb5-832c-600af549a8bb" />


Sau cài đặt, các thành phần sẽ nằm ở:

| Thành phần | Vị trí |
|------------|--------|
| App | `/Applications/AppLocker.app` |
| Helper | `/Library/PrivilegedHelperTools/AppLockerHelper` |
| LaunchDaemon | `/Library/LaunchDaemons/com.TranPhuong319.AppLockerHelper.plist` |

Helper sẽ được đăng ký và tự động chạy bằng launchd.

---

## 🧪 Log

Bạn có thể xem bằng: `Console.app` 

---

## ❌ Gỡ cài đặt hoàn toàn

- Chạy file AppLocker.pkg
- Ở bước Loại cài đặt, bỏ chọn **Cài đặt AppLocker**
- Nhấn tiếp tục, nhập mật khẩu quản trị viên

<img width="623" height="445" alt="image" src="https://github.com/user-attachments/assets/f20baffd-7040-457c-8af7-639ca7d10630" />

Phần mềm sẽ được gỡ cài đặt.

> Lưu ý: Trước khi gỡ cài đặt, vui lòng đảm bảo mọi ứng dụng đều được **mở khoá**



---

## 🧑‍💻 Tác giả

**Trần Phương**  
GitHub: [@TranPhuong319](https://github.com/TranPhuong319)
