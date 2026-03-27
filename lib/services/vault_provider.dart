import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:gal/gal.dart'; // 🔴 NATIVE GALLERY ENGINE
import '../models/password_entry.dart';
import '../models/media_entry.dart';

class VaultProvider with ChangeNotifier {
  List<PasswordCategory> _categories = [];
  List<MediaFolder> _mediaFolders = [];

  final _uuid = const Uuid();
  bool _isUnlocked = false;
  bool _isMediaUnlocked = false;
  bool _isPickingMedia = false;
  bool _dataCorrupted = false;

  String? _activePin;

  List<PasswordCategory> get categories => _categories;
  List<MediaFolder> get mediaFolders => _mediaFolders;
  bool get isMediaUnlocked => _isMediaUnlocked;
  bool get isPickingMedia => _isPickingMedia;
  bool get dataCorrupted => _dataCorrupted;

  Future<File> _getDatabaseFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/vaultx_core.enc');
  }

  Future<enc.Key> _deriveKey(String pin) async {
    final dir = await getApplicationDocumentsDirectory();
    final saltFile = File('${dir.path}/vaultx_install.salt');

    Uint8List salt;
    if (await saltFile.exists()) {
      salt = await saltFile.readAsBytes();
    } else {
      final rng = Random.secure();
      salt = Uint8List.fromList(List.generate(32, (_) => rng.nextInt(256)));
      await saltFile.writeAsBytes(salt, flush: true);
    }

    List<int> key = [...salt, ...utf8.encode(pin)];
    for (int i = 0; i < 100000; i++) {
      key = sha256.convert(key).bytes;
    }
    return enc.Key(Uint8List.fromList(key));
  }

  Future<String> _encrypt(String plaintext, String pin) async {
    final key = await _deriveKey(pin);
    final iv = enc.IV.fromSecureRandom(16);       
    final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
    final encrypted = encrypter.encrypt(plaintext, iv: iv);
    return '${base64.encode(iv.bytes)}:${encrypted.base64}';
  }

  Future<String> _decrypt(String stored, String pin) async {
    final key = await _deriveKey(pin);
    final separatorIndex = stored.indexOf(':');
    if (separatorIndex != -1) {
      // Split on FIRST colon only — base64 can't contain colons but
      // future format changes or corruption could add extra colons.
      final ivBase64 = stored.substring(0, separatorIndex);
      final cipherBase64 = stored.substring(separatorIndex + 1);
      final iv = enc.IV(base64.decode(ivBase64));
      final ciphertext = enc.Encrypted.fromBase64(cipherBase64);
      final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
      return encrypter.decrypt(ciphertext, iv: iv);
    } else {
      // Legacy fallback: old zero-IV format
      final iv = enc.IV.fromLength(16);
      final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
      return encrypter.decrypt(enc.Encrypted.fromBase64(stored), iv: iv);
    }
  }

  Future<void> unlockVault(String pin) async {
    _activePin = pin;
    _isUnlocked = true;
    await _loadData();
  }

  void unlockMediaVault() {
    _isMediaUnlocked = true;
    notifyListeners();
  }

  void lockMediaVault() {
    _isMediaUnlocked = false;
    notifyListeners();
  }

  void wipeMemory() {
    if (_isPickingMedia) return;
    _isUnlocked = false;
    _isMediaUnlocked = false; 
    _activePin = null;        
    _categories.clear();
    _mediaFolders.clear();    
    notifyListeners();
  }

  Future<void> _loadData() async {
    if (!_isUnlocked || _activePin == null) return;

    try {
      final dbFile = await _getDatabaseFile();
      if (!await dbFile.exists()) {
        _categories = [];
        _mediaFolders = [];
        _dataCorrupted = false;
        notifyListeners();
        return;
      }

      final stored = await dbFile.readAsString();
      if (stored.isEmpty) throw Exception('Database file is empty.');

      final decrypted = await _decrypt(stored, _activePin!);
      final decoded = json.decode(decrypted);

      List<PasswordCategory> loadedCategories = [];
      List<MediaFolder> loadedMedia = [];

      if (decoded is Map) {
        if (decoded['categories'] != null) {
          for (var cat in (decoded['categories'] as List)) {
            try { loadedCategories.add(PasswordCategory.fromJson(Map<String, dynamic>.from(cat as Map))); } catch (_) {}
          }
        }
        if (decoded['mediaFolders'] != null) {
          for (var folder in (decoded['mediaFolders'] as List)) {
            try { loadedMedia.add(MediaFolder.fromJson(Map<String, dynamic>.from(folder as Map))); } catch (_) {}
          }
        }
      }

      _categories = loadedCategories;
      _mediaFolders = loadedMedia;
      _dataCorrupted = false;
    } catch (e) {
      final dbFile = await _getDatabaseFile();
      if (await dbFile.exists()) _dataCorrupted = true;
      _categories = [];
      _mediaFolders = [];
    }
    notifyListeners();
  }

  Future<void> _saveData() async {
    if (!_isUnlocked || _activePin == null) return;
    if (_dataCorrupted) return;

    try {
      final dataToSave = {
        'categories': _categories.map((e) => e.toJson()).toList(),
        'mediaFolders': _mediaFolders.map((e) => e.toJson()).toList(),
      };
      final jsonString = json.encode(dataToSave);
      final encrypted = await _encrypt(jsonString, _activePin!);
      final dbFile = await _getDatabaseFile();
      await dbFile.writeAsString(encrypted, flush: true);
    } catch (e) {
      debugPrint('VAULT SAVE ERROR: $e');
    }
  }

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
      _categories[index] = PasswordCategory(id: _categories[index].id, name: newName, entries: _categories[index].entries);
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
          id: old.id, title: newTitle ?? old.title, email: newEmail ?? old.email, password: newPassword ?? old.password,
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

  Future<void> addMedia(String folderType, String sourcePath, {String? thumbnailPath}) async {
    if (!_isUnlocked || !_isMediaUnlocked) return;

    // Whitelist allowed extensions — reject anything else
    final rawExt = p.extension(sourcePath).toLowerCase();
    const allowedExtensions = {'.jpg', '.jpeg', '.png', '.gif', '.webp', '.mp4', '.mov', '.mkv', '.3gp'};
    final fileExtension = allowedExtensions.contains(rawExt) ? rawExt : '.bin';

    final folderName = folderType == 'photo' ? 'Photos' : 'Videos';
    var folderIndex = _mediaFolders.indexWhere((f) => f.type == folderType);
    if (folderIndex == -1) {
      _mediaFolders.add(MediaFolder(id: _uuid.v4(), name: folderName, type: folderType, items: []));
      folderIndex = _mediaFolders.length - 1;
    }

    final directory = await getApplicationDocumentsDirectory();
    final hiddenMediaDir = Directory('${directory.path}/vaultx_media');
    if (!await hiddenMediaDir.exists()) await hiddenMediaDir.create();

    final nomediaFile = File('${hiddenMediaDir.path}/.nomedia');
    if (!await nomediaFile.exists()) await nomediaFile.create();

    final newFileName = '${_uuid.v4()}$fileExtension';
    final securePath = '${hiddenMediaDir.path}/$newFileName';

    await File(sourcePath).copy(securePath);
    try { await File(sourcePath).delete(); } catch (_) {}

    String? secureThumbPath;
    if (thumbnailPath != null) {
      final thumbExt = p.extension(thumbnailPath);
      final newThumbName = 'thumb_${_uuid.v4()}$thumbExt';
      secureThumbPath = '${hiddenMediaDir.path}/$newThumbName';
      await File(thumbnailPath).copy(secureThumbPath);
      try { await File(thumbnailPath).delete(); } catch (_) {}
    }

    _mediaFolders[folderIndex].items.add(MediaItem(id: _uuid.v4(), path: securePath, thumbnailPath: secureThumbPath));
    await _saveData();
    notifyListeners();
  }

  Future<void> renameMediaFolder(String id, String newName) async {
    if (!_isUnlocked || !_isMediaUnlocked) return;
    final index = _mediaFolders.indexWhere((f) => f.id == id);
    if (index != -1) {
      _mediaFolders[index].name = newName;
      await _saveData();
      notifyListeners();
    }
  }

  Future<void> deleteMedia(String folderId, String itemId) async {
    if (!_isUnlocked || !_isMediaUnlocked) return;
    final fIndex = _mediaFolders.indexWhere((f) => f.id == folderId);
    if (fIndex != -1) {
      final itemIndex = _mediaFolders[fIndex].items.indexWhere((i) => i.id == itemId);
      if (itemIndex != -1) {
        final item = _mediaFolders[fIndex].items[itemIndex];
        try {
          if (await File(item.path).exists()) await File(item.path).delete();
          if (item.thumbnailPath != null && await File(item.thumbnailPath!).exists()) {
            await File(item.thumbnailPath!).delete();
          }
        } catch (_) {}
        _mediaFolders[fIndex].items.removeAt(itemIndex);
        await _saveData();
        notifyListeners();
      }
    }
  }

  // 🔴 NATIVE RECOVERY: Drops the file back into the camera roll using 'gal'
  Future<bool> recoverMedia(String folderId, MediaItem item) async {
    if (!_isUnlocked || !_isMediaUnlocked) return false;
    try {
      final extension = p.extension(item.path).toLowerCase();
      final isVideo = extension == '.mp4' || extension == '.mkv' || extension == '.mov';

      if (isVideo) {
        await Gal.putVideo(item.path);
      } else {
        await Gal.putImage(item.path);
      }

      await deleteMedia(folderId, item.id);
      return true;
    } catch (e) {
      debugPrint('Recovery error: $e');
      return false;
    }
  }

  Future<void> deleteVaultFile() async {
    final dir = await getApplicationDocumentsDirectory();
    final dbFile = File("${dir.path}/vaultx_core.enc");
    final saltFile = File("${dir.path}/vaultx_install.salt");
    final mediaDir = Directory("${dir.path}/vaultx_media");
    if (await dbFile.exists()) await dbFile.delete();
    if (await saltFile.exists()) await saltFile.delete();
    if (await mediaDir.exists()) await mediaDir.delete(recursive: true);
  }

  Future<void> changeMasterPin(String newPin) async {
    if (!_isUnlocked || _activePin == null) return;
    _activePin = newPin;
    await _saveData();
  }
}