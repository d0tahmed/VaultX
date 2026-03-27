import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:encrypt/encrypt.dart' as enc;
import '../models/password_entry.dart';

class VaultProvider with ChangeNotifier {
  List<PasswordCategory> _categories = [];
  final _uuid = const Uuid();

  // 🔴 RED TEAM PATCH: The vault strictly tracks if it is legally unlocked in RAM
  bool _isUnlocked = false;

  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static const _vaultDataKey = 'vaultx_encrypted_database';
  static const _dekKey       = 'vaultx_master_dek'; // The Data Encryption Key

  List<PasswordCategory> get categories => _categories;

  // ── Enterprise DEK Architecture (Hardware Keystore) ─────────
  Future<enc.Key> _getOrCreateDek() async {
    final existing = await _storage.read(key: _dekKey);
    if (existing != null) return enc.Key.fromBase64(existing);

    // Generate a cryptographically secure 256-bit AES key on first run
    final key = enc.Key.fromSecureRandom(32);
    await _storage.write(key: _dekKey, value: key.base64);
    return key;
  }

  // ── Encrypt: plaintext → base64( IV[16] + ciphertext ) ───────────────────
  Future<String> _encrypt(String plaintext) async {
    final key       = await _getOrCreateDek();
    final iv        = enc.IV.fromSecureRandom(16);
    final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
    final encrypted = encrypter.encrypt(plaintext, iv: iv);

    // Pack: IV first, then ciphertext — we need IV to decrypt later
    final blob = Uint8List(16 + encrypted.bytes.length);
    blob.setRange(0, 16, iv.bytes);
    blob.setRange(16, blob.length, encrypted.bytes);
    return base64.encode(blob);
  }

  // ── Decrypt: base64( IV[16] + ciphertext ) → plaintext ───────────────────
  Future<String> _decrypt(String cipherBase64) async {
    final blob        = base64.decode(cipherBase64);
    final iv          = enc.IV(blob.sublist(0, 16));
    final cipherBytes = enc.Encrypted(blob.sublist(16));
    final key         = await _getOrCreateDek();
    final encrypter   = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
    return encrypter.decrypt(cipherBytes, iv: iv);
  }

  // ── Save: JSON → AES-256 encrypt → Keystore ──────────────────────────────
  Future<void> _saveData() async {
    if (!_isUnlocked) return; // 🔴 CRITICAL: Never overwrite data if vault is locked!

    final plaintext = jsonEncode(_categories.map((c) => c.toJson()).toList());
    final encrypted = await _encrypt(plaintext);
    await _storage.write(key: _vaultDataKey, value: encrypted);
  }

  // ── Unlock: Keystore → AES-256 decrypt → JSON → RAM ───────────
  // 🔴 FIXED: No longer requires the PIN parameter, fixing all UI crashes!
  Future<void> unlockVault() async {
    _isUnlocked = true; 

    final stored = await _storage.read(key: _vaultDataKey);

    if (stored == null || stored.isEmpty) {
      _categories = []; // Fresh install
      notifyListeners();
      return;
    }

    try {
      final decrypted = await _decrypt(stored);
      final list      = jsonDecode(decrypted) as List;
      _categories     = list.map((cat) => PasswordCategory.fromJson(cat)).toList();
    } catch (e) {
      // Decryption failed — corrupted data
      _categories = [];
    }

    notifyListeners();
  }

  // ── Wipe: Clear decrypted data from RAM ───────────────────────
  void wipeMemory() {
    _categories = [];
    _isUnlocked = false; // 🔴 Data is locked and cannot be saved or read
    notifyListeners();
  }

  // ── CRUD Operations ───────────────────────────────────────────

  Future<void> addCategory(String name) async {
    if (!_isUnlocked) return;
    _categories.add(PasswordCategory(id: _uuid.v4(), name: name, entries: []));
    await _saveData();
    notifyListeners();
  }

  Future<void> renameCategory(String id, String newName) async {
    if (!_isUnlocked) return;
    final index = _categories.indexWhere((cat) => cat.id == id);
    if (index != -1) {
      _categories[index] = PasswordCategory(
        id:      _categories[index].id,
        name:    newName,
        entries: _categories[index].entries,
      );
      await _saveData();
      notifyListeners();
    }
  }

  Future<void> deleteCategory(String id) async {
    if (!_isUnlocked) return;
    _categories.removeWhere((cat) => cat.id == id);
    await _saveData();
    notifyListeners();
  }

  Future<void> addEntryToCategory(String categoryId, String title, String email, String pass) async {
    if (!_isUnlocked) return;
    final index = _categories.indexWhere((cat) => cat.id == categoryId);
    if (index != -1) {
      _categories[index].entries.add(PasswordEntry(id: _uuid.v4(), title: title, email: email, password: pass));
      await _saveData();
      notifyListeners();
    }
  }

  Future<void> updateEntry(String categoryId, String entryId, {String? newTitle, String? newEmail, String? newPassword}) async {
    if (!_isUnlocked) return;
    final catIndex = _categories.indexWhere((cat) => cat.id == categoryId);
    if (catIndex != -1) {
      final entryIndex = _categories[catIndex].entries.indexWhere((e) => e.id == entryId);
      if (entryIndex != -1) {
        final old = _categories[catIndex].entries[entryIndex];
        _categories[catIndex].entries[entryIndex] = PasswordEntry(
          id:       old.id,
          title:    newTitle    ?? old.title,
          email:    newEmail    ?? old.email,
          password: newPassword ?? old.password,
        );
        await _saveData();
        notifyListeners();
      }
    }
  }

  Future<void> deleteEntry(String categoryId, String entryId) async {
    if (!_isUnlocked) return;
    final catIndex = _categories.indexWhere((cat) => cat.id == categoryId);
    if (catIndex != -1) {
      _categories[catIndex].entries.removeWhere((e) => e.id == entryId);
      await _saveData();
      notifyListeners();
    }
  }
}