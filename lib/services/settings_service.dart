import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsService extends ChangeNotifier {
  static const _customAnnouncementKey = 'custom_announcement';
  static const _prefetchLookaheadKey = 'prefetch_lookahead';

  SharedPreferences? _preferences;
  bool _disposed = false;
  String _customAnnouncement = '';
  int _prefetchLookahead = 3;

  String get customAnnouncement => _customAnnouncement;
  int get prefetchLookahead => _prefetchLookahead;

  Future<void> load() async {
    final preferences = await SharedPreferences.getInstance();
    _preferences = preferences;
    _customAnnouncement =
        preferences.getString(_customAnnouncementKey)?.trim() ?? '';
    _prefetchLookahead =
        (preferences.getInt(_prefetchLookaheadKey) ?? 3).clamp(1, 3).toInt();
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

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
