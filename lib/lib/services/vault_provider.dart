import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as enc;
import '../models/password_entry.dart';

class VaultProvider with ChangeNotifier {
  List<PasswordCategory> _categories = [];
  final _uuid = const Uuid();

  // The PIN-derived key — held in RAM only, never stored
  // Set when the user unlocks, cleared by wipeMemory()
  String? _activePin;

  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static const _vaultDataKey = 'vaultx_encrypted_database';
  static const _saltKey      = 'vaultx_crypto_salt';

  List<PasswordCategory> get categories => _categories;

  // ── Salt: one random 32-byte salt per install, stored in Keystore ─────────
  Future<Uint8List> _getOrCreateSalt() async {
    final existing = await _storage.read(key: _saltKey);
    if (existing != null) return base64.decode(existing);

    final rng  = Random.secure();
    final salt = Uint8List.fromList(List.generate(32, (_) => rng.nextInt(256)));
    await _storage.write(key: _saltKey, value: base64.encode(salt));
    return salt;
  }

  // ── Key derivation: PIN + salt → 32-byte AES key (50k SHA-256 rounds) ────
  Future<enc.Key> _deriveKey(String pin) async {
    final salt = await _getOrCreateSalt();
    List<int> key = [...salt, ...utf8.encode(pin)];
    for (int i = 0; i < 50000; i++) {
      key = sha256.convert(key).bytes;
    }
    return enc.Key(Uint8List.fromList(key));
  }

  // ── Encrypt: plaintext → base64( IV[16] + ciphertext ) ───────────────────
  Future<String> _encrypt(String plaintext, String pin) async {
    final key       = await _deriveKey(pin);
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
  Future<String> _decrypt(String cipherBase64, String pin) async {
    final blob        = base64.decode(cipherBase64);
    final iv          = enc.IV(blob.sublist(0, 16));
    final cipherBytes = enc.Encrypted(blob.sublist(16));
    final key         = await _deriveKey(pin);
    final encrypter   = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
    return encrypter.decrypt(cipherBytes, iv: iv);
  }

  // ── Save: JSON → AES-256 encrypt → Keystore ──────────────────────────────
  Future<void> _saveData() async {
    if (_activePin == null) return; // Never save if not unlocked

    final plaintext = jsonEncode(_categories.map((c) => c.toJson()).toList());
    final encrypted = await _encrypt(plaintext, _activePin!);
    await _storage.write(key: _vaultDataKey, value: encrypted);
  }

  // ── Unlock: Keystore → AES-256 decrypt → JSON → objects in RAM ───────────
  Future<void> unlockVault(String pin) async {
    _activePin = pin; // Keep PIN in RAM for subsequent saves

    final stored = await _storage.read(key: _vaultDataKey);

    if (stored == null || stored.isEmpty) {
      _categories = []; // Fresh install — no data yet
      notifyListeners();
      return;
    }

    try {
      final decrypted = await _decrypt(stored, pin);
      final list      = jsonDecode(decrypted) as List;
      _categories     = list.map((cat) => PasswordCategory.fromJson(cat)).toList();
    } catch (_) {
      // Decryption failed — wrong PIN or corrupted data
      // Don't crash the app, just start empty
      _categories = [];
    }

    notifyListeners();
  }

  // ── Wipe: clear decrypted data AND the PIN from RAM ───────────────────────
  void wipeMemory() {
    _categories = [];
    _activePin  = null; // ✅ Key is gone — data is unreadable until next unlock
    notifyListeners();
  }

  // ── CRUD — all async now so _saveData() can await properly ───────────────

  Future<void> addCategory(String name) async {
    _categories.add(PasswordCategory(id: _uuid.v4(), name: name, entries: []));
    await _saveData();
    notifyListeners();
  }

  Future<void> renameCategory(String id, String newName) async {
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
    _categories.removeWhere((cat) => cat.id == id);
    await _saveData();
    notifyListeners();
  }

  Future<void> addEntryToCategory(
    String categoryId, String title, String email, String pass,
  ) async {
    final index = _categories.indexWhere((cat) => cat.id == categoryId);
    if (index != -1) {
      _categories[index].entries.add(
        PasswordEntry(id: _uuid.v4(), title: title, email: email, password: pass),
      );
      await _saveData();
      notifyListeners();
    }
  }

  Future<void> updateEntry(
    String categoryId,
    String entryId, {
    String? newTitle,
    String? newEmail,
    String? newPassword,
  }) async {
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
    final catIndex = _categories.indexWhere((cat) => cat.id == categoryId);
    if (catIndex != -1) {
      _categories[catIndex].entries.removeWhere((e) => e.id == entryId);
      await _saveData();
      notifyListeners();
    }
  }
}