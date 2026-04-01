# 🛡️ VaultX: HIGHLY SECURED - Version 2.0.0

**VaultX** is a paranoid, locally-hosted password and media manager built for Android. Unlike commercial cloud-based password managers, VaultX assumes your device will eventually fall into the hands of a malicious actor. It is engineered with a hybrid zero-knowledge architecture, aggressive RAM watchdogs, and physical threat mitigations to ensure your data survives—or self-destructs—on your terms.

--------------------------

## ❓ Why use VaultX? (The Value Proposition)

Commercial cloud password managers protect you from remote hackers, but they fail against physical threats: the "Evil Maid" attack, a stolen unlocked phone, or forced coercion. VaultX is built for **physical threat modeling**.

1. **Zero Cloud Risk:** Your data never leaves your device. No servers to be breached, no databases to be leaked.
2. **Immune to OS Scrapers:** VaultX aggressively zeroes out plaintext strings from the Dart heap and flushes RAM the millisecond the app loses focus. Memory scrapers will find nothing.
3. **Active Counter-Intelligence:** If someone tries to guess your PIN, VaultX doesn't just lock them out—it silently photographs them and logs the breach.
4. **Hardware-Backed Protection:** By tying failure counts to the Android Keystore, VaultX prevents rooted devices from resetting the brute-force counter.

--------------------------

## 🚀 The Evolution: V1 vs. V2

VaultX V2 is a complete architectural rewrite focusing on memory safety and active physical defense. 

| Feature | VaultX V1 (The Baseline) | VaultX V2 (Red-Team Architecture) |
| :--- | :--- | :--- |
| **Encryption Key** | Saved to Secure Storage (Vulnerable to OS wipes) | **Zero-Knowledge PBKDF2** (Derived in real-time via 100k SHA-256 iterations) |
| **Media Playback** | Exported to Gallery to view | **In-App Secure Player** (Decrypted in RAM, never touches OS Gallery) |
| **Brute-Force Defense** | Basic Lockout Timer | **Poison Pill** (Cryptographic shredding of all databases after 8 fails) |
| **Intruder Logging** | None | **The Honeypot** (Silent front-camera capture on 3rd failed attempt) |
| **Memory Management** | Relied on Garbage Collection | **Aggressive Zeroing** (Plaintext strings explicitly wiped from heap on `dispose`) |
| **OS Indexing** | Media hidden by obscure folders | **Ghost Protocol** (Random UUIDs + `.nomedia` OS blinding) |

--------------------------

## 🧠 Core Security Features

### 1. Zero-Knowledge PBKDF2 Encryption
Your master AES key is never saved anywhere on the device. Instead, VaultX mathematically derives it in real-time by hashing your 6-digit PIN and a local salt 100,000 times. When you close the app, the key evaporates from RAM.

### 2. The Poison Pill (Cryptographic Shredding)
VaultX tracks authentication failures inside the hardware-backed Android Keystore. After 8 incorrect attempts, it triggers a self-destruct sequence—permanently deleting the encrypted database, the salt, and the media directory. 

### 3. The Honeypot (Intruder Selfie)
If an unauthorized user enters an incorrect PIN 3 times, VaultX silently boots a headless camera process, snaps a photo using the front-facing camera without a shutter sound, and logs the timestamp in a hidden "Breach Logs" dashboard.

### 4. Hardware-Level RAM Watchdog
The exact millisecond the app is pushed to the background, minimized, or the screen turns off, the `wipeMemory()` lifecycle function triggers. Active session keys are flushed, the UI is locked, and biometric/PIN authentication is immediately required.

### 5. k-Anonymity Deep Scanning
VaultX audits your vault for breached passwords using the *Have I Been Pwned* database via strict k-Anonymity. It hashes your password locally (SHA-1) and only transmits the first 5 characters over the network to check for leaks.

### 6. Advanced Clipboard Wiping
When a password is copied, VaultX places it on the clipboard and initiates a strict 15-second countdown. Once the timer hits zero, it blindly overwrites the clipboard, preventing OEM keyboards or clipboard managers from maintaining a history.

### 7. Environment Integrity
Upon cold boot, VaultX scans the device's operating system. If it detects that the phone has been rooted or compromised (which would allow an attacker to bypass the Keystore), VaultX blocks all access and locks down the environment.
--------------------------

## 🛠️ Getting Started / Compilation

To build the VaultX Red-Team payload for your local device:

1. **Clone the repository:**
   ```bash
   git clone [https://github.com/yourgithubusername/VaultX-Secure.git](https://github.com/yourgithubusername/VaultX-Secure.git)
   cd VaultX-Secure
