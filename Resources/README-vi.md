<div align="center">
  
  <img width="160" height="160" alt="Biểu tượng AppLocker" src="../docs/images/Icon.png" />

  # AppLocker
  
  **Khóa Ứng Dụng & Bảo Vệ Quyền Riêng Tư Cấp Kernel Trên macOS**

  [![CI](https://github.com/TranPhuong319/AppLocker/actions/workflows/main.yml/badge.svg)](https://github.com/TranPhuong319/AppLocker/actions/workflows/main.yml)
  ![Phiên bản](https://img.shields.io/github/v/release/TranPhuong319/AppLocker)
  [![Tải từ Releases](https://img.shields.io/github/v/release/TranPhuong319/AppLocker?include_prereleases&label=alpha)](https://github.com/TranPhuong319/AppLocker/releases)
  ![Lượt tải](https://img.shields.io/github/downloads/TranPhuong319/AppLocker/total)
  ![GitHub issues](https://img.shields.io/github/issues/TranPhuong319/AppLocker)
  ![GitHub pull requests](https://img.shields.io/github/issues-pr/TranPhuong319/AppLocker)
  ![Last Commit](https://img.shields.io/github/last-commit/TranPhuong319/AppLocker)
  ![Nền tảng](https://img.shields.io/badge/platform-macOS%2014.0%2B-blue?logo=apple)
  ![Swift](https://img.shields.io/badge/Swift-6.0%2B-orange?logo=swift)
  ![Giấy phép](https://img.shields.io/badge/license-Apache%202.0-green)

</div>

<p align="center">
  <b>Ngôn ngữ:</b>
  <a href="../README.md">English</a> •
  <a href="README-vi.md">Tiếng Việt</a>
</p>

---

## 🎬 Trải Nghiệm Trực Tiếp (Live Demo)

<div align="center">
  <img src="../docs/images/demo.gif" alt="Demo hoạt động của AppLocker" width="85%" style="border-radius: 12px; box-shadow: 0 8px 24px rgba(0,0,0,0.2);" />
  <p><i>Chặn bắt tức thì ở cấp độ Kernel, xác thực Touch ID mượt mà và mở khóa hàng loạt</i></p>
</div>

---

## 📖 Câu Chuyện Khởi Nguồn Của AppLocker

> *"Mình năm nay 15 tuổi. Mỗi khi cho bạn bè hay người khác mượn máy Mac, mình luôn lo lắng về việc dữ liệu cá nhân hay các ứng dụng riêng tư bị mở xem. macOS không có sẵn cơ chế khóa từng ứng dụng chi tiết. Vì vậy mình quyết định tự tay xây dựng một giải pháp."*

Bắt đầu từ con số 0 về lập trình hệ thống, mình đã tự tìm tòi, nghiên cứu cách hoạt động của **Apple Endpoint Security Framework** và cơ chế xử lý tín hiệu **POSIX** (học hỏi từ các dự án mã nguồn mở như Google Santa). Từ ý tưởng và kiến trúc đó, mình kết hợp cùng các **AI Coding Agents** để hiện thực hóa code Swift, giải quyết các bài toán bảo mật phức tạp, cùng review và liên tục sửa các lỗi phát sinh. AppLocker là minh chứng cho việc bất kỳ ai cũng có thể làm ra sản phẩm công nghệ thực thụ từ chính nhu cầu của mình.

---

## ✨ Tính Năng Nổi Bật

- 🔒 **Không Sửa Đổi File Nhị Phân (Zero Binary Modification)**: Khóa mọi ứng dụng mà không cần can thiệp vào file thực thi hay làm hỏng chữ ký số (Code Signature).
- ⚡ **Chặn ở Cấp Độ Kernel (Kernel-Level Interception)**: Khai thác sức mạnh của **Apple Endpoint Security Framework** (`AUTH_SIGNAL` & `NOTIFY_EXEC`) chạy dưới dạng System Extension quyền root.
- 🛡️ **Đóng Băng Tiến Trình An Toàn (POSIX Signal)**: Lập tức tạm dừng tiến trình bằng tín hiệu `SIGSTOP` trước khi cửa sổ ứng dụng kịp xuất hiện; tự động khôi phục bằng `SIGCONT` khi xác thực thành công hoặc hủy bằng `SIGKILL` khi từ chối.
- 👆 **Xác Thực Sinh Trắc Học Linh Hoạt**: Hỗ trợ Touch ID, Apple Watch hoặc mật khẩu hệ thống thông qua `LocalAuthentication`.
- 📦 **Xác Thực Hàng Loạt Thông Minh (Batch Auth)**: Tự động phát hiện và gộp nhiều ứng dụng bị khóa khởi chạy cùng lúc vào một cửa sổ duy nhất, giúp duyệt mở khóa nhanh chóng chỉ trong 1 lần xác thực.
- 🛡️ **Cơ Chế Chống Can Thiệp (Anti-Tampering)**: Ngăn chặn hành vi gửi tín hiệu tắt tiến trình (`SIGKILL`/`SIGSTOP`) vào Daemon bảo mật và ứng dụng chính, đồng thời khóa an toàn các file cấu hình.
- 🎨 **Giao Diện Liquid Glass Chuẩn Apple**: Thiết kế trực quan, hiện đại bằng SwiftUI và AppKit, hỗ trợ Dark Mode tự nhiên và đa ngôn ngữ (`en`, `vi`).
- 🚀 **Hiệu Năng Cao & Tối Ưu Bộ Nhớ**: Cache icon ứng dụng in-memory (`AppIconProvider`), tối ưu tìm kiếm Spotlight debounced (`NSMetadataQuery`), và cô lập luồng chặt chẽ với `@MainActor`.

---

## 📸 Hình Ảnh Giao Diện Thực Tế

| Bảng Điều Khiển Chính | Xác Thực Đơn Lẻ |
| :---: | :---: |
| <img src="../docs/images/screenshots/screenshot-main.png" width="460" alt="Bảng Điều Khiển Chính" /> | <img src="../docs/images/screenshots/screenshot-auth.png" width="460" alt="Xác Thực Đơn Lẻ" /> |
| **Quản lý danh sách ứng dụng cần khóa** | **Hộp thoại xác thực Touch ID / Mật khẩu** |

| Xác Thực Hàng Loạt (Batch Auth) | Menu Bar Tiện Lợi |
| :---: | :---: |
| <img src="../docs/images/screenshots/screenshot-mutiple-auth.png" width="460" alt="Xác Thực Hàng Loạt" /> | <img src="../docs/images/screenshots/screenshot-menubar.png" width="460" alt="Menu Bar" /> |
| **Gom nhóm và xử lý mở khóa nhiều app cùng lúc** | **Truy cập nhanh và xem trạng thái trên thanh Menu** |

---

## 🏛️ Kiến Trúc Hệ Thống

AppLocker được phân tách thành 3 tầng thành phần rõ ràng:

1. **`AppLocker` (Ứng Dụng Chính)**: Giao diện người dùng (SwiftUI + AppKit) quản lý cấu hình, `LocalAuthentication`, Menu Bar và điều phối cửa sổ Batch Auth trên `@MainActor`.
2. **`ESExtension` (Endpoint Security Daemon)**: System Extension chạy với quyền root (System Daemon). Xử lý các sự kiện `NOTIFY_EXEC`, `NOTIFY_EXIT`, và sự kiện chống can thiệp (`AUTH_SIGNAL`, `AUTH_FILE`).
3. **`Shared Core`**: Chia sẻ các giao thức XPC (`ESAppProtocol`, `ESXPCProtocol`), mật mã học ECDSA P-256 (`KeychainHelper`), trích xuất CDHash (`CDHashHelper`) và hệ thống ghi log tập trung (`os.Logger`).

### 🔄 Quy Trình Chặn Bắt & Mở Khóa

```mermaid
sequenceDiagram
    autonumber
    actor User as Người dùng
    participant TargetApp as Ứng dụng bị khóa (VD: Safari)
    participant Kernel as macOS Kernel / ES Subsystem
    participant ESExt as ESExtension (Root Daemon)
    participant AppLocker as AppLocker (Ứng dụng chính)

    User->>TargetApp: Mở ứng dụng
    TargetApp->>Kernel: execve()
    Kernel->>ESExt: Sự kiện NOTIFY_EXEC (Nhận PID > 0 & CDHash)
    ESExt->>TargetApp: POSIX kill(PID, SIGSTOP) [Đóng băng tiến trình]
    ESExt->>AppLocker: Gửi XPC notifyBlockedExec(name, path, cdhash, pid)
    AppLocker->>User: Hiển thị Touch ID / Mật khẩu (BatchAuthView)
    alt Xác Thực Thành Công
        User->>AppLocker: Quét Touch ID thành công
        AppLocker->>ESExt: Gửi XPC processPendingApps(approvedPIDs: [PID])
        ESExt->>TargetApp: POSIX kill(PID, SIGCONT) [Cho phép chạy tiếp]
    else Hủy / Hết Thời Gian Chờ
        AppLocker->>ESExt: Gửi XPC processPendingApps(rejectedPIDs: [PID])
        ESExt->>TargetApp: POSIX kill(PID, SIGKILL) [Buộc dừng tiến trình]
    end
```

### 🔐 An Ninh & Chống Can Thiệp

- **Chặn Tín Hiệu & Chống Can Thiệp (`AUTH_SIGNAL`)**: Giám sát và từ chối các tín hiệu POSIX trái phép (`SIGCONT`, `SIGKILL`, `SIGSTOP`) từ bên ngoài nhắm vào các ứng dụng đang bị đóng băng, Daemon bảo mật hoặc AppLocker, ngăn chặn tuyệt đối việc vượt rào bảo vệ.
- **Xác Thực Hai Chiều ECDSA P-256 (Mutual Authentication)**: Giao tiếp XPC giữa `AppLocker` và `ESExtension` được bảo vệ bằng cơ chế bắt tay mã hóa sinh khóa ngẫu nhiên (Nonce) qua `CryptoKit` (`P256.Signing`).
- **Xác Minh Tính Toàn Vẹn CDHash**: Trích xuất `audit_token` của tiến trình gọi từ Kernel và đối chiếu với CDHash của file nhị phân trên đĩa nhằm ngăn chặn giả mạo kết nối XPC.

---

## 💻 Yêu Cầu Hệ Thống

- **Hệ Điều Hành**: Tối thiểu là macOS 14.0 (Sonoma) trở lên.
- **Kiến Trúc Phần Cứng**: Apple Silicon (M1/M2/M3/M4) và Intel (x86_64).

> [!NOTE]
> **Lưu Ý Về Entitlements**: Apple yêu cầu tài khoản **Apple Developer Program** trả phí ($99/năm) và xét duyệt thủ công cho quyền `com.apple.developer.endpoint-security.client`.
> 
> Để phát triển cục bộ và thử nghiệm mã nguồn mở mà không cần profile trả phí, cần tắt **System Integrity Protection (SIP)** (`csrutil disable` trong Recovery Mode đối với Intel và Hạ cấp bảo mật đối với Apple Silicon) để System Extension có thể đăng ký vào hệ thống.

---

## 🚀 Cài Đặt & Sử Dụng

### Cách 1: Tải Bản Cài Đặt Có Sẵn (Release)
1. Tải bản `.dmg` mới nhất từ mục [Releases](https://github.com/TranPhuong319/AppLocker/releases).
2. Kéo và thả file **AppLocker.app** vào thư mục `/Applications`.
3. Khởi chạy ứng dụng và làm theo hướng dẫn trên màn hình để cấp quyền System Extension.
4. Xem hướng dẫn chi tiết tại [Hướng dẫn sử dụng](../docs/USAGE-vi.md).

### Cách 2: Tự Build Từ Mã Nguồn (Xcode)
```bash
# Clone repository về máy
git clone https://github.com/TranPhuong319/AppLocker.git
cd AppLocker

# Mở dự án trong Xcode
open AppLocker.xcodeproj
```
1. Chọn scheme `AppLocker`.
2. Bấm **⌘ + R** để build và chạy.

---

## 👨‍💻 Tác Giả

**Trần Phương** 
- GitHub: [@TranPhuong319](https://github.com/TranPhuong319)  
- Facebook: [@TranPhuong2504](https://facebook.com/tranphuong2504)  

*Đặc biệt cảm ơn dự án mã nguồn mở [Santa](https://github.com/google/santa) của Google vì các tiêu chuẩn tham khảo mẫu mực về kiến trúc Endpoint Security.*

---

## 📄 Giấy Phép

Dự án này được phân phối dưới giấy phép **Apache License 2.0** — xem file [LICENSE](../LICENSE) để biết thêm chi tiết.
