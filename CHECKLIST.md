# AppLocker Review & Refactoring Checklist

Checklist này tổng hợp các hạng mục cần rà soát, dọn dẹp (pruning) và gia cố (hardening) kỹ thuật cho codebase **AppLocker**, áp dụng nguyên lý **Ponytail (Minimal, Native First, YAGNI)** và **macOS Security Best Practices**.

---

## 🧹 1. Dọn dẹp Code thừa & Cắt tỉa Legacy (Ponytail Pruning)

- [x] **Xóa Legacy Config Fallback trong ESExtension**:
  - **File:** `ESExtension/Engine/ESManager+Config.swift`
  - **Hành động:** 
    - Xóa hằng số `static let legacyConfigPath`.
    - Xóa nhánh fallback `if newCDHashes.isEmpty && fileManager.fileExists(atPath: ESManager.legacyConfigPath)`.
    - Xóa các hàm helper cũ: `parseLegacyConfigData()`, `parseLegacyDictConfig()`, `parseLegacyArrayConfig()`.
  - **Lý do:** `ConfigStore.swift` ở Main App đã đảm nhiệm migration sang format theo từng UID và tự động xóa file cũ.

---

## ⚡ 2. Tối ưu Hiệu năng & Giảm Tải Kernel (Performance Optimization)

- [ ] **Mute System Paths ở Tầng Kernel (`ESTamper`)**:
  - **File:** `ESExtension/Engine/ESModularClients.swift`
  - **Hành động:** Gọi `es_mute_path_prefix` lúc khởi tạo `ESTamper` cho các đường dẫn hệ thống/build không cần giám sát:
    - `/System`
    - `/usr`
    - `/Library/Developer`
    - `/private/var/db`
  - **Lý do:** Giảm 80-90% lượng event `AUTH_OPEN` rác đẩy lên `authorizationProcessingQueue` ở user-space.

---

## 🛡️ 3. Gia cố Xử lý POSIX Signals & PID Safety (Hardening)

- [ ] **Thêm POSIX Liveness Check trước khi gửi Signal**:
  - **File:** `ESExtension/Engine/ESManager+PendingProcess.swift`
  - **Hành động:** Trong `processApprovedPIDs` và `processRejectedPIDs`, bổ sung điều kiện `kill(pid, 0) == 0`:
    ```swift
    guard pid > 0, kill(pid, 0) == 0 else { continue }
    ```
  - **Lý do:** Ngăn chặn việc gửi `SIGCONT`/`SIGKILL` nhầm nếu tiến trình đã chết và PID bị kernel tái sử dụng (PID recycling).

- [ ] **Đánh giá Bổ sung `audit_token` / `pidversion` Tracking**:
  - **File:** `ESExtension/Engine/ESManager+PendingProcess.swift`
  - **Hành động:** Lưu trữ `audit_token_t` cùng với `pid_t` trong `pendingVerificationPIDs` để xác thực danh tính tuyệt đối khi batch approval diễn ra sau thời gian chờ dài.

---

## 🔐 4. Phục hồi Trạng thái Khóa ECDSA & XPC Resync (IPC Resilience)

- [ ] **Tự Động Re-Handshake khi XPC Gián Đoạn**:
  - **Files:** `AppLocker/EndpointSecurity/ESXPCClient.swift` & `Shared/Security/KeychainHelper.swift`
  - **Hành động:** 
    - Đặt cờ `isHandshakeCompleted = false` trong `interruptionHandler` và `invalidationHandler`.
    - Khi có request XPC mới sau khi restart một trong hai tiến trình, tự động trigger lại luồng bắt tay ECDSA P-256 thay vì để lỗi chữ ký số xảy ra.
  - **Lý do:** `KeychainHelper` lưu trữ key trên RAM (ephemeral), cần tự hồi phục khi daemon/app restart.

---

## ⏱️ 5. Đồng bộ Hóa Concurrency & SwiftLint

- [ ] **Đơn giản hóa Quản lý Timer trong XPCServer**:
  - **File:** `AppLocker/EndpointSecurity/XPCServer.swift`
  - **Hành động:** Rà soát `countdownTimer` và `pendingDebounceTimer`, đảm bảo mọi thao tác mutate state và UI binding đều diễn ra trên `@MainActor` theo chuẩn Swift 6.
- [ ] **Kiểm tra Lint Toàn diện**:
  - **Hành động:** Chạy `swiftlint lint` trên toàn bộ project và đảm bảo đạt **0 errors, 0 warnings**.
