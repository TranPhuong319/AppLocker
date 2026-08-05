# Hướng dẫn sử dụng AppLocker

[ [English](USAGE.md) | Tiếng Việt ]

AppLocker là một công cụ bảo mật native dành cho macOS, giúp can thiệp vào quá trình khởi chạy ứng dụng và yêu cầu người dùng xác thực (Touch ID hoặc Mật khẩu hệ thống) trước khi ứng dụng được thực thi.

---

## Yêu cầu hệ thống

- **Phiên bản macOS**: macOS 13 (Ventura) trở lên.
- **System Integrity Protection (SIP)**: Bắt buộc phải **tắt** để cho phép System Extension Endpoint Security (ES) tải và can thiệp vào quá trình khởi chạy tiến trình ở cấp độ Kernel.

---

## Cài đặt ban đầu

### 1. Tắt System Integrity Protection (SIP)
1. Tắt máy Mac của bạn.
2. Khởi động vào Chế độ khôi phục (Recovery Mode):
   - **Apple Silicon (M1/M2/M3/M4)**: Nhấn và giữ **Nút nguồn** cho đến khi dòng chữ "Loading startup options" xuất hiện, sau đó chọn **Options > Continue**.
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

## Quản lý các ứng dụng bị khóa

Truy cập cửa sổ quản lý bất kỳ lúc nào bằng cách nhấp vào **biểu tượng khóa AppLocker (`🔒`)** trên thanh menu macOS và chọn **Manage the application list…** (hoặc nhấn `Cmd + Shift + L`).  
*Lưu ý: Mở cửa sổ quản lý yêu cầu xác thực.*

### Khóa ứng dụng
1. Trong cửa sổ chính của AppLocker, nhấp vào nút **`+` (Dấu cộng)** ở phần header.
2. Chọn ứng dụng từ danh sách **Applications** (Ứng dụng) hoặc **System Applications** (Ứng dụng hệ thống).
3. Hoặc nhấp vào **Select Other Applications…** để duyệt và chọn bất kỳ ứng dụng `.app` tùy chỉnh nào bằng Finder.
4. Nhấp vào **Lock** để kích hoạt bảo vệ.

### Mở khóa ứng dụng
1. Nhấp vào biểu tượng **`-` (Dấu trừ / Thùng rác)** bên cạnh ứng dụng trong danh sách đã khóa.
2. Ứng dụng sẽ được đưa vào **Danh sách chờ mở khóa** (Unlock Waiting List).
3. Nhấp vào thanh thông báo ở phía dưới (*"Waiting to unlock N application(s)..."*).
4. Kiểm tra danh sách chờ và nhấp vào **Unlock** để xác nhận xóa khỏi danh sách khóa.

---

## Khởi chạy ứng dụng bị khóa

1. Mở bất kỳ ứng dụng bị khóa nào như bình thường (qua Finder, Dock, Spotlight hoặc Launchpad).
2. AppLocker sẽ can thiệp và chặn lượt khởi chạy trước khi tiến trình bắt đầu.
3. Hộp thoại xác thực sẽ xuất hiện yêu cầu **Touch ID** hoặc **Mật khẩu người dùng macOS**.
4. Sau khi xác thực thành công, ứng dụng sẽ khởi chạy ngay lập tức. Nếu xác thực thất bại hoặc bị hủy, quá trình khởi chạy sẽ bị dừng lại.

---

## Phím tắt & Điều khiển trên thanh Menu

| Phím tắt | Thao tác Menu | Mô tả |
| :--- | :--- | :--- |
| `Cmd + Shift + L` | **Manage the application list…** | Mở cửa sổ quản lý danh sách ứng dụng (yêu cầu xác thực). |
| `Cmd + ,` | **Settings…** | Cấu hình kiểm tra cập nhật tự động, tải về và kênh cập nhật (Stable / Beta). |
| — | **Check for Updates…** | Kiểm tra cập nhật phần mềm thủ công. |
| — | **About AppLocker** | Xem phiên bản ứng dụng hiện tại và thông tin nhà phát triển. |
| — | **Uninstall AppLocker…** | Hủy ủy quyền system extension, gỡ bỏ dịch vụ chạy ngầm và gỡ cài đặt AppLocker sạch sẽ. |
| `Option` (Giữ) | **Reset AppLocker…** | Đặt lại toàn bộ cài đặt và xóa danh sách ứng dụng bị khóa (yêu cầu xác thực). |

---

## Gỡ cài đặt

Để gỡ bỏ sạch sẽ AppLocker, system extension, background agent và cài đặt:

### Khuyên dùng (Gỡ cài đặt tự động)
1. Đảm bảo tất cả ứng dụng bị khóa đã được mở khóa.
2. Nhấp vào **biểu tượng khóa AppLocker (`🔒`)** trên thanh menu macOS.
3. Chọn **Uninstall AppLocker…**.
4. Xác nhận thông báo gỡ cài đặt. AppLocker sẽ tự động:
   - Hủy ủy quyền và gỡ tải Endpoint Security system extension.
   - Dừng và gỡ bỏ background agent (`launchd`).
   - Dọn dẹp các tệp cấu hình của ứng dụng.
   - Di chuyển `AppLocker.app` vào Thùng rác (Trash).
5. Khởi động lại máy Mac khi được yêu cầu để hoàn tất dọn dẹp hệ thống.

### Dọn dẹp thủ công
Nếu bạn đã xóa `AppLocker.app` thủ công trước đó:
1. Xóa các tệp cấu hình và tệp launch agent còn sót lại:
   ```bash
   rm -rf ~/Library/Application\ Support/AppLocker
   rm -rf ~/Library/LaunchAgents/com.TranPhuong319.AppLocker.agent.plist
   ```
2. (Tùy chọn) Bật lại System Integrity Protection (SIP) nếu bạn không còn cần cơ chế can thiệp tiến trình:
   - Khởi động vào **Recovery Mode** -> **Utilities > Terminal**.
   - Chạy lệnh `csrutil enable` và khởi động lại máy Mac của bạn.

---

## Xử lý sự cố & Đặt lại

### System Extension bị chặn
- Đảm bảo SIP đã được tắt (lệnh `csrutil status` trong Terminal sẽ hiển thị `System Integrity Protection status: disabled.`).
- Truy cập **System Settings > Privacy & Security** và cho phép system extension ở mục Security.

### Đặt lại cấu hình
Nếu bạn cần khôi phục AppLocker về cài đặt mặc định:
1. Giữ phím `Option` trong khi nhấp vào biểu tượng thanh menu `🔒`.
2. Nhấp vào **Reset AppLocker…** và thực hiện xác thực.
3. Hoặc xóa thủ công tệp cấu hình:
   ```bash
   rm -rf ~/Library/Application\ Support/AppLocker
   ```
