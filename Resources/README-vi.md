

<div align="center">
  
  <img width="256" height="256" alt="AppIcon-macOS-Default-256x256@2x" src="https://github.com/user-attachments/assets/18b552f7-5e87-467e-b680-6f92de4374b3" />

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

- [English](/README.md)

- Tiếng Việt

**AppLocker** là công cụ bảo mật cho macOS giúp khóa ứng dụng và yêu cầu xác thực trước khi chạy.

## Giới thiệu
**AppLocker** là một công cụ bảo mật dành cho macOS, cho phép khóa các ứng dụng bất kỳ và yêu cầu người dùng xác thực trước khi ứng dụng có thể chạy.  
Cơ chế khóa được triển khai thông qua kỹ thuật ngụy trang và Endpoint Security của Apple.

## Tính năng chính
- Khóa các ứng dụng trên macOS
- Yêu cầu xác thực người dùng trước khi chạy ứng dụng
- Hỗ trợ khóa bằng Endpoint Security
- Có chế độ khóa thay thế thông qua launcher

## Nền tảng hỗ trợ
- macOS 13 (Ventura) trở lên

## Yêu cầu hệ thống
- Phải tắt System Integrity Protection (SIP) để sử dụng cơ chế khóa bằng Endpoint Security

## Cài đặt
- Kéo và thả ứng dụng AppLocker vào thư mục `/Applications`

## Sử dụng
- Khi khởi chạy lần đầu (với SIP đã tắt), có hai lựa chọn:
  - **Chế độ Endpoint Security (ES)**: cần bật trong System Extension
  - **Chế độ Launcher**: cần bật Extension cho tất cả người dùng (có thể yêu cầu nhập mật khẩu quản trị)


## Giấy phép
Apache License 2.0

## Tác giả

**Trần Phương**  
> GitHub: [@TranPhuong319](https://github.com/TranPhuong319) &nbsp;&middot;&nbsp;
> Facebook: [@TranPhuong2504](https://facebook.com/tranphuong2504)
