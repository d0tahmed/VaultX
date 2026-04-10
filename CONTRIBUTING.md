# Contributing to VaultX

Thank you for your interest in contributing to VaultX! This document provides guidelines and instructions for contributing.

---

## 🚀 Getting Started

1. **Fork** the repository on GitHub
2. **Clone** your fork locally:
   ```bash
   git clone https://github.com/YOUR_USERNAME/VaultX.git
   cd VaultX
   ```
3. **Install** dependencies:
   ```bash
   flutter pub get
   ```
4. **Create** a feature branch:
   ```bash
   git checkout -b feature/your-feature-name
   ```

---

## 📐 Code Guidelines

### Style
- Follow the [Dart Style Guide](https://dart.dev/effective-dart/style)
- Run `flutter analyze` before submitting — ensure zero warnings
- Use the existing design system tokens from `lib/theme/app_theme.dart`

### Commit Messages
Use [Conventional Commits](https://www.conventionalcommits.org/) format:

```
feat: add biometric fallback for older devices
fix: resolve clipboard wipe race condition
docs: update security architecture diagram
refactor: extract encryption logic to service layer
```

### Security
- **Never** log sensitive data (PINs, keys, passwords) — even in debug mode
- **Always** use `VaultProvider.wipeMemory()` patterns when handling plaintext
- **Test** on a physical device for biometric and camera features

---

## 🔄 Pull Request Process

1. **Update** documentation if your changes affect the public API or user-facing behavior
2. **Ensure** `flutter analyze` passes with no issues
3. **Describe** your changes clearly in the PR description
4. **Link** any related issues using `Fixes #123` or `Closes #123`

---

## 🐛 Reporting Bugs

When reporting bugs, please include:
- Device model and Android version
- Flutter version (`flutter --version`)
- Steps to reproduce
- Expected vs. actual behavior
- Screenshots or screen recordings if applicable

---

## 💡 Feature Requests

Feature requests are welcome! Please open an issue with:
- A clear description of the feature
- The problem it solves
- Any mockups or examples if applicable

---

## 📄 License

By contributing to VaultX, you agree that your contributions will be licensed under the [MIT License](LICENSE).
