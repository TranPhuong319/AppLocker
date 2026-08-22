# Hướng dẫn sử dụng AppLocker

[ [English](USAGE.md) | Tiếng Việt ]

AppLocker là một công cụ bảo mật native dành cho macOS, giúp can thiệp vào quá trình khởi chạy ứng dụng và yêu cầu người dùng xác thực (Touch ID, Apple Watch hoặc Mật khẩu hệ thống) trước khi ứng dụng được thực thi.

---

## 💻 Yêu cầu hệ thống

- **Phiên bản macOS**: macOS 14.0 (Sonoma) trở lên.
- **Kiến trúc phần cứng**: Apple Silicon (M1/M2/M3/M4) và Intel (x86_64).
- **System Integrity Protection (SIP)**: Cần được **tắt** (do extension Endpoint Security trong bản phát triển local chưa có chứng chỉ trả phí từ Apple).

---

## 🛠️ Cài đặt ban đầu

### 1. Tắt System Integrity Protection (SIP)
1. Tắt máy Mac của bạn hoàn toàn.
2. Khởi động vào **Chế độ khôi phục (Recovery Mode)**:
   - **Apple Silicon (M1/M2/M3/M4)**: Nhấn và giữ **Nút nguồn** cho đến khi dòng chữ *"Loading startup options"* xuất hiện $\rightarrow$ chọn **Options > Continue** $\rightarrow$ Vào menu **Utilities > Startup Security Utility** $\rightarrow$ Chọn ổ đĩa $\rightarrow$ Chọn **Reduced Security** (Hạ cấp bảo mật).
   - **Máy Mac chạy chip Intel**: Giữ tổ hợp phím `Cmd + R` ngay sau khi bật nguồn cho đến khi logo Apple xuất hiện.
3. Trên thanh menu phía trên, mở **Utilities > Terminal** (Tiện ích > Terminal).
4. Chạy lệnh:
   ```bash
   csrutil disable
   ```
5. Khởi động lại máy Mac của bạn.

### 2. Bật System Extension
1. Kéo `AppLocker.app` vào thư mục `/Applications` và khởi chạy ứng dụng.
2. Khi được yêu cầu, cho phép cài đặt System Extension.
3. Mở **System Settings > Privacy & Security** (Cài đặt hệ thống > Quyền riêng tư & Bảo mật).
4. Cuộn xuống phần **Security** (Bảo mật) và nhấp vào **Allow** (Cho phép) bên cạnh thông báo phần mềm từ nhà phát triển *"Tran Phuong"*.

---

## 📋 Quản lý các ứng dụng bị khóa

Truy cập cửa sổ quản lý bất kỳ lúc nào bằng cách nhấp vào **biểu tượng khóa AppLocker (`🔒`)** trên thanh menu macOS và chọn **Manage the application list…** (hoặc nhấn `Cmd + Shift + L`).  
*(Lưu ý: Mở cửa sổ quản lý yêu cầu xác thực Touch ID / Mật khẩu).*

<div align="center">
  <img src="images/screenshots/screenshot-main.png" width="80%" alt="Giao diện chính quản lý ứng dụng" />
  <p><i>Cửa sổ quản lý danh sách ứng dụng đã khóa</i></p>
</div>

### Khóa ứng dụng
1. Trong cửa sổ chính của AppLocker, nhấp vào nút **`+` (Dấu cộng)** ở phần header.
2. Chọn ứng dụng từ danh sách **Applications** (Ứng dụng) hoặc **System Applications** (Ứng dụng hệ thống).
3. Hoặc nhấp vào **Select Other Applications…** để duyệt và chọn bất kỳ ứng dụng `.app` tùy chỉnh nào bằng Finder.
4. Nhấp vào **Lock** để kích hoạt bảo vệ.

### Mở khóa ứng dụng
1. Nhấp vào biểu tượng **`-` (Dấu trừ / Thùng rác)** bên cạnh ứng dụng trong danh sách đã khóa.
2. Ứng dụng sẽ được đưa vào **Danh sách chờ mở khóa** (*Unlock Waiting List*).
3. Nhấp vào thanh thông báo ở phía dưới (*"Waiting to unlock N application(s)..."*).
4. Kiểm tra danh sách chờ và nhấp vào **Unlock** để xác nhận xóa khỏi danh sách khóa.

---

## 🚀 Khởi chạy ứng dụng bị khóa

1. Mở bất kỳ ứng dụng bị khóa nào như bình thường (qua Finder, Dock, Spotlight hoặc Launchpad).
2. AppLocker sẽ can thiệp và đóng băng lượt khởi chạy ở tầng Kernel trước khi tiến trình hiển thị giao diện.
3. Hộp thoại xác thực sẽ xuất hiện yêu cầu **Touch ID**, **Apple Watch** hoặc **Mật khẩu người dùng**:
   - **Xác thực đơn lẻ**: Khi mở 1 ứng dụng.
   - **Xác thực hàng loạt (Batch Auth)**: Khi mở nhiều ứng dụng bị khóa cùng lúc, AppLocker sẽ tự động gom nhóm để bạn duyệt 1 lần.
4. Sau khi xác thực thành công, ứng dụng sẽ tiếp tục chạy ngay lập tức (`SIGCONT`). Nếu hủy hoặc thất bại, tiến trình sẽ bị hủy an toàn (`SIGKILL`).

| Xác thực đơn lẻ | Xác thực hàng loạt (Batch Auth) |
| :---: | :---: |
| <img src="images/screenshots/screenshot-auth.png" width="380" alt="Hộp thoại xác thực đơn lẻ" /> | <img src="images/screenshots/screenshot-mutiple-auth.png" width="380" alt="Xác thực hàng loạt" /> |

---

## ⚡ Phím tắt & Điều khiển trên thanh Menu Bar

<div align="center">
  <img src="images/screenshots/screenshot-menubar.png" width="50%" alt="Menu Bar AppLocker" />
  <p><i>Thao tác nhanh trên thanh Menu Bar</i></p>
</div>

| Phím tắt | Thao tác Menu | Mô tả |
| :--- | :--- | :--- |
| `Cmd + Shift + L` | **Manage the application list…** | Mở cửa sổ quản lý danh sách ứng dụng (yêu cầu xác thực). |
| `Cmd + ,` | **Settings…** | Cấu hình kiểm tra cập nhật tự động, tải về và kênh cập nhật (Stable / Beta). |
| — | **Check for Updates…** | Kiểm tra cập nhật phần mềm thủ công. |
| — | **About AppLocker** | Xem phiên bản ứng dụng hiện tại và thông tin nhà phát triển. |
| — | **Uninstall AppLocker…** | Hủy ủy quyền system extension, gỡ bỏ dịch vụ chạy ngầm và gỡ cài đặt AppLocker sạch sẽ. |
| `Option` (Giữ) | **Reset AppLocker…** | Đặt lại toàn bộ cài đặt và xóa danh sách ứng dụng bị khóa (yêu cầu xác thực). |

---

## 🗑️ Gỡ cài đặt

Để gỡ bỏ sạch sẽ AppLocker, system extension, background agent và cài đặt:

### Cách khuyên dùng (Gỡ cài đặt tự động)
1. Nhấp vào **biểu tượng khóa AppLocker (`🔒`)** trên thanh menu macOS.
2. Chọn **Uninstall AppLocker…**.
3. Xác nhận thông báo gỡ cài đặt. AppLocker sẽ tự động:
   - Hủy ủy quyền và gỡ tải Endpoint Security system extension (yêu cầu xác thực Admin từ hệ thống).
   - Dừng và gỡ bỏ background agent (`launchd`).
   - Dọn dẹp các tệp cấu hình của ứng dụng (`/Users/Shared/AppLocker`).
   - Di chuyển `AppLocker.app` vào Thùng rác (Trash).

### Dọn dẹp thủ công
Nếu bạn đã xóa `AppLocker.app` thủ công trước đó:
1. Xóa các tệp cấu hình và tệp launch agent còn sót lại:
   ```bash
   sudo rm -rf /Users/Shared/AppLocker
   rm -rf ~/Library/LaunchAgents/com.TranPhuong319.AppLocker.agent.plist
   ```
2. (Tùy chọn) Bật lại System Integrity Protection (SIP) nếu bạn không còn cần cơ chế can thiệp tiến trình:
   - Khởi động vào **Recovery Mode** -> **Utilities > Terminal**.
   - Chạy lệnh `csrutil enable` và khởi động lại máy Mac của bạn.

---

## 🔧 Xử lý sự cố & Đặt lại

### System Extension bị chặn
- Đảm bảo SIP đã được tắt (lệnh `csrutil status` trong Terminal sẽ hiển thị `System Integrity Protection status: disabled.`).
- Truy cập **System Settings > Privacy & Security** và cho phép system extension ở mục Security.

### Đặt lại cấu hình
> [!WARNING]
> Việc đặt lại sẽ xóa toàn bộ danh sách khóa ứng dụng và cấu hình chung của **tất cả người dùng** trên máy Mac này.

Nếu bạn cần khôi phục AppLocker về cài đặt mặc định:
1. Giữ phím `Option` trong khi nhấp vào biểu tượng thanh menu `🔒`.
2. Nhấp vào **Reset AppLocker…** và thực hiện xác thực.
3. Hoặc xóa thủ công tệp cấu hình dùng chung:
   ```bash
   sudo rm -rf /Users/Shared/AppLocker
   ```
