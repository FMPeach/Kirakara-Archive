import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsService extends ChangeNotifier {
  SettingsService({required String initialCacheDirectoryPath})
      : _cacheDirectoryPath = initialCacheDirectoryPath;

  static const _customAnnouncementKey = 'custom_announcement';
  static const _prefetchLookaheadKey = 'prefetch_lookahead';
  static const _cacheDirectoryKey = 'cache_directory';

  SharedPreferences? _preferences;
  bool _disposed = false;
  String _customAnnouncement = '';
  int _prefetchLookahead = 3;
  String _cacheDirectoryPath;

  String get customAnnouncement => _customAnnouncement;
  int get prefetchLookahead => _prefetchLookahead;
  String get cacheDirectoryPath => _cacheDirectoryPath;

  static Future<String> resolveCacheDirectory(String defaultPath) async {
    final preferences = await SharedPreferences.getInstance();
    final saved = preferences.getString(_cacheDirectoryKey)?.trim() ?? '';
    final selected = saved.isEmpty ? defaultPath : saved;
    try {
      final directory = Directory(selected).absolute;
      directory.createSync(recursive: true);
      return directory.path;
    } on FileSystemException {
      final fallback = Directory(defaultPath).absolute;
      fallback.createSync(recursive: true);
      await preferences.setString(_cacheDirectoryKey, fallback.path);
      return fallback.path;
    }
  }

  Future<void> load() async {
    final preferences = await SharedPreferences.getInstance();
    _preferences = preferences;
    _customAnnouncement =
        preferences.getString(_customAnnouncementKey)?.trim() ?? '';
    _prefetchLookahead =
        (preferences.getInt(_prefetchLookaheadKey) ?? 3).clamp(1, 3).toInt();
    final cacheDirectory =
        preferences.getString(_cacheDirectoryKey)?.trim() ?? '';
    if (cacheDirectory.isNotEmpty) {
      _cacheDirectoryPath = cacheDirectory;
    }
    if (!_disposed) notifyListeners();
  }

  Future<void> setCustomAnnouncement(String value) async {
    final normalized = value.trim();
    if (_customAnnouncement == normalized) return;
    _customAnnouncement = normalized;
    if (!_disposed) notifyListeners();
    await _preferences?.setString(_customAnnouncementKey, normalized);
  }

  Future<void> setPrefetchLookahead(int value) async {
    final normalized = value.clamp(1, 3).toInt();
    if (_prefetchLookahead == normalized) return;
    _prefetchLookahead = normalized;
    if (!_disposed) notifyListeners();
    await _preferences?.setInt(_prefetchLookaheadKey, normalized);
  }

  Future<void> setCacheDirectoryPath(String value) async {
    final normalized = value.trim();
    if (normalized.isEmpty || _cacheDirectoryPath == normalized) return;
    _cacheDirectoryPath = normalized;
    if (!_disposed) notifyListeners();
    final preferences = _preferences ?? await SharedPreferences.getInstance();
    _preferences = preferences;
    await preferences.setString(_cacheDirectoryKey, normalized);
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
