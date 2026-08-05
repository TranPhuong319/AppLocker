<div align="center">
  
  <img width="256" height="256" alt="Biểu tượng AppLocker" src="../docs/images/Icon.png" />

# AppLocker

[![CI](https://github.com/TranPhuong319/AppLocker/actions/workflows/main.yml/badge.svg)](https://github.com/TranPhuong319/AppLocker/actions/workflows/main.yml)
![Version](https://img.shields.io/github/v/release/TranPhuong319/AppLocker)
[![Download from https://github.com/TranPhuong319/AppLocker/releases](https://img.shields.io/github/v/release/TranPhuong319/AppLocker?include_prereleases&label=alpha)](https://github.com/TranPhuong319/AppLocker/releases)
![Downloads](https://img.shields.io/github/downloads/TranPhuong319/AppLocker/total)
![GitHub issues](https://img.shields.io/github/issues/TranPhuong319/AppLocker)
![GitHub pull requests](https://img.shields.io/github/issues-pr/TranPhuong319/AppLocker)
![Last Commit](https://img.shields.io/github/last-commit/TranPhuong319/AppLocker)

</div>

## Ngôn ngữ Khả dụng

- [English](../README.md)

- Tiếng Việt

**AppLocker** là một công cụ bảo mật cho macOS giúp khóa ứng dụng và yêu cầu người dùng xác thực trước khi chạy.  

## Tổng quan
**AppLocker** là một công cụ bảo mật dành cho macOS, giúp ngăn các ứng dụng được chọn chạy trừ khi người dùng đã xác thực.  
Cơ chế khóa ứng dụng được triển khai thông qua kỹ thuật ngụy trang và Apple Endpoint Security.

## Tính năng chính
- Khóa các ứng dụng tùy chỉnh trên macOS
- Bắt buộc xác thực trước khi ứng dụng thực thi
- Hỗ trợ khóa bằng Endpoint Security
- Chế độ khóa thay thế dựa trên launcher

## Nền tảng hỗ trợ
- macOS 13 (Ventura) trở lên

## Yêu cầu hệ thống
- Phải tắt System Integrity Protection (SIP) để sử dụng cơ chế khóa dựa trên Endpoint Security

## Cài đặt
- Kéo và thả ứng dụng AppLocker vào thư mục `/Applications`

## Sử dụng
Để xem hướng dẫn chi tiết, vui lòng tham khảo [Hướng dẫn sử dụng](../docs/USAGE-vi.md).

- Khi khởi chạy lần đầu (với SIP đã tắt), có hai chế độ:
  - **Chế độ Endpoint Security (ES)**: yêu cầu bật System Extension
  - **Chế độ Launcher**: yêu cầu bật Extension cho tất cả người dùng (có thể yêu cầu mật khẩu quản trị viên)

## Giấy phép
Apache License 2.0

## Tác giả

**Trần Phương**  
> GitHub: [@TranPhuong319](https://github.com/TranPhuong319) &nbsp;&middot;&nbsp;
> Facebook: [@TranPhuong2504](https://facebook.com/tranphuong2504)
