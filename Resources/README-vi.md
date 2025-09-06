# 🔐 AppLocker – macOS Application Locker

**AppLocker** là công cụ bảo mật cho macOS giúp bạn khóa bất kỳ ứng dụng nào bằng cơ chế ngụy trang và yêu cầu xác thực trước khi truy cập. AppLocker giúp bảo vệ quyền riêng tư và tránh việc người khác mở ứng dụng trái phép.

---

## Tính năng nổi bật
- 🔐 Khoá bất kỳ ứng dụng nào trên macOS
- 🕵️‍♂️ Ngụy trang ứng dụng để tránh bị mở trái phép
- ✅ Yêu cầu xác thực (Touch ID / mật khẩu) trước khi mở ứng dụng
- 📋 Quản lý danh sách ứng dụng đã khóa dễ dàng từ menu bar

---

## 📦 Cài đặt
1. Tải file `.dmg` từ [Releases](https://github.com/TranPhuong319/AppLocker/releases)
2. Mở file `.dmg` và kéo AppLocker vào thư mục **Applications**
3. Mở AppLocker lần đầu:
   - Vì ứng dụng chưa được notarized, macOS sẽ chặn mở
   - Mở **System Preferences → Security & Privacy → General**
   - Click **Open Anyway** để cho phép chạy AppLocker
   - Sau đó, nhập mật khẩu của quản trị viên để cho phép

---

## ⚠️ Lưu ý khi gỡ cài đặt
- Trước khi xóa AppLocker, đảm bảo **mở khoá tất cả các ứng dụng**
- Kéo AppLocker vào **Thùng rác** để gỡ cài đặt hoàn toàn

---

## 💻 Yêu cầu hệ thống
- macOS Ventura 13.5 trở lên
- Không cần quyền đặc biệt, nhưng cần cấp quyền **Privacy** khi mở AppLocker lần đầu

---

## 📜 Xem log
- Mở `Console.app` → tìm log của AppLocker để xem các hoạt động như mở/khoá ứng dụng và xác thực thành công/thất bại

---

## 🧑‍💻 Tác giả & Hỗ trợ
**Trần Phương**  
GitHub: [@TranPhuong319](https://github.com/TranPhuong319)
