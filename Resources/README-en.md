
<div align="center">
  
  <img width="256" height="256" alt="AppIcon-macOS-Default-256x256@2x" src="https://github.com/user-attachments/assets/18b552f7-5e87-467e-b680-6f92de4374b3" />

# AppLocker

</div>

**AppLocker** is a macOS security tool that locks applications and requires user authentication before execution.  

## Overview
**AppLocker** is a security tool for macOS that prevents selected applications from running unless the user is authenticated.  
The application locking mechanism is implemented using masquerading techniques and Apple Endpoint Security.

## Key Features
- Lock arbitrary macOS applications
- Enforce authentication before application execution
- Supports Endpoint Security–based locking
- Alternative launcher-based locking mode

## Supported Platform
- macOS 13 (Ventura) or later

## System Requirements
- System Integrity Protection (SIP) must be disabled to use Endpoint Security–based locking

## Installation
- Drag and drop the AppLocker application into `/Applications`

## Usage
- On first launch (with SIP disabled), two modes are available:
  - **Endpoint Security (ES) mode**: requires enabling the System Extension
  - **Launcher mode**: requires enabling the Extension for all users (administrator password may be required)

## License
Apache License 2.0

## Author

**Trần Phương**  
> GitHub: [@TranPhuong319](https://github.com/TranPhuong319) &nbsp;&middot;&nbsp;
> Facebook: [@TranPhuong2504](https://facebook.com/tranphuong2504)
