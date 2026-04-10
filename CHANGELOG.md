# Changelog

All notable changes to VaultX will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [3.0.0] — 2026-04-10

### Added
- Complete UI overhaul with "Vaulted Horizon" design system
- Security dashboard with real-time vault health analytics
- Password strength distribution charts (fl_chart)
- Encrypted media vault with separate PIN protection
- In-app secure photo & video player (decrypted in RAM only)
- Intruder selfie capture on failed authentication
- Environment integrity check (root detection)
- Biometric authentication support

### Changed
- Migrated encryption key derivation to zero-knowledge PBKDF2 (100K iterations)
- Upgraded cryptographic shredding to trigger after 8 failed attempts
- Improved RAM watchdog — session keys flushed on app lifecycle change

### Security
- AES-256-CBC encryption with runtime-only key derivation
- k-Anonymity breach scanning via Have I Been Pwned API
- 15-second auto-wipe clipboard on password copy

---

## [2.0.0] — 2025

### Added
- Red-Team security architecture
- Poison Pill (cryptographic shredding)
- Honeypot (intruder selfie)
- Hardware-level RAM Watchdog
- Ghost Protocol (UUID file naming + `.nomedia`)

### Changed
- Full architectural rewrite focusing on memory safety

---

## [1.0.0] — 2024

### Added
- Initial release
- Basic password vault with AES encryption
- PIN-based authentication
- Secure storage integration
