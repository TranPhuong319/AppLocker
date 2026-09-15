# Security Policy

## Supported Versions

We provide security updates and patches for versions running on Apple Endpoint Security architecture. Older releases utilizing the legacy executable wrapper launcher have been deprecated and removed.

| Version | Supported | Notes |
| ------- | :-------: | ----- |
| 1.9.x   | :white_check_mark: | Latest release branch |
| 1.6.0 - 1.8.x | :white_check_mark: | Supported (Apple Endpoint Security framework) |
| < 1.6.0 | :x: | Legacy launcher wrapper (Deprecated & removed) |

---

## Security Model & Threat Scope

AppLocker enforces application execution control at the kernel boundary via Apple's **Endpoint Security (`auth_exec`)** framework and macOS system extension architecture.

### In-Scope Vulnerabilities
- Bypassing application interception while **System Integrity Protection (SIP)** is enabled and the AppLocker System Extension is active and approved.
- Privilege escalation or unauthorized tampering with AppLocker configuration stores from non-root processes.
- IPC / XPC impersonation, injection, or sandbox escape allowing unauthenticated control over the helper or system extension.

### Out-of-Scope Scenarios
- Systems where **System Integrity Protection (SIP)** has been disabled, as macOS kernel security guarantees no longer hold.
- Physical attacks, hardware extraction, or attacks requiring root/kernel compromises that already bypass macOS system-level protections.
- Process termination through standard superuser (`sudo kill -9`) where the threat actor already possesses unrestricted root capabilities.

---

## Reporting a Vulnerability

If you discover a security vulnerability in this project, please report it responsibly by following the steps below:

1. **Report Location**  
   Submit details about the vulnerability privately to our security team [through GitHub Security Advisories](https://github.com/TranPhuong319/AppLocker/security/advisories/new).

2. **Information to Provide**  
   Include the following information to help us understand and address the issue quickly:  
   - Detailed description of the vulnerability and attack vector  
   - Reproducible proof-of-concept (PoC) or step-by-step reproduction instructions  
   - Target macOS versions and hardware architectures (Apple Silicon / Intel)  
   - Impact assessment (potential severity and affected assets)  
   - Any suggested remediations or patches (optional)  

3. **Response Timeline**  
   - You can expect an initial acknowledgment of your report within 48 hours.  
   - We will provide updates on verification, patch development, and release timelines.  

4. **Disclosure Policy**  
   - We commit to keeping reports confidential until a patch is available.  
   - Coordinated public disclosure will be published through GitHub Security Advisories once mitigations are released.  

5. **Thank You**  
   We deeply appreciate the efforts of security researchers in keeping AppLocker and the community secure.

---

*This Security Policy will be updated periodically to reflect any changes in supported versions or reporting procedures.*
