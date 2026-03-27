🛡️ VaultX | Hardened Open-Source Password Manager
VaultX is a military-grade, offline-first password management solution built with Flutter. Designed for the security-conscious user, it implements advanced cryptographic architectures and anti-forensic measures to ensure your data remains your own—even if your device falls into the wrong hands.

🚀 Key Security Features
🔐 Enterprise-Grade Cryptography
DEK (Data Encryption Key) Architecture: Utilizes a 256-bit AES Master Key stored within the Android Hardware Keystore (TEE).

Zero-Knowledge Design: Your Master PIN is never stored; it acts only as a gatekeeper to the hardware-backed encryption layer.

CBC Mode with Secure IVs: Every encryption cycle uses a unique Initialization Vector to prevent pattern-based attacks.

🚫 Anti-Exploit & Hardening
Biometric-Only Policy: Disables insecure OS-level "Device PIN/Pattern" fallbacks, neutralizing shoulder-surfing and Evil Maid attacks.

Screen Masking (FLAG_SECURE): Blocks screenshots, screen recordings, and prevents data leaks in the Android Task Switcher.

Input Sanitization: Disables third-party keyboard "learning" and cloud-syncing to prevent keylogging at the OS level.

🧹 Real-Time Forensic Protection
Memory Assassination: Decrypted data is wiped from RAM the millisecond the app loses focus or is minimized.

Secure Clipboard Service: Implements a "Blind Wipe" protocol that clears the system clipboard 15 seconds after any copy operation.

🛠️ Tech Stack
Framework: Flutter

State Management: Provider

Storage: Flutter Secure Storage (AES-256)

Hardware: Android Trusted Execution Environment (TEE)

👨‍💻 Developer
made with ❤️ by d0tahmed
