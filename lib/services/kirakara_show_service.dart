import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../domain/media_asset.dart';
import '../domain/song.dart';
import 'kirakara_show_ffi.dart';
import 'playback_service.dart';

class KirakaraShowService extends ChangeNotifier {
  KirakaraShowService({
    required PlaybackService playbackService,
  }) : _playbackService = playbackService;

  final PlaybackService _playbackService;
  KirakaraShowFFI? _ffi;
  String? _loadedItemId;
  bool _started = false;

  /// The latest frame as RGBA8 pixels. null when no frame is ready.
  Uint8List? get latestFrame => _latestFrame;
  Uint8List? _latestFrame;

  /// Call this once after the engine DLL is available.
  void start() {
    if (_started) return;
    _started = true;
    try {
      _ffi = KirakaraShowFFI();
    } catch (e) {
      debugPrint('KirakaraShowService: failed to load engine DLL: $e');
      return;
    }
    _playbackService.addListener(_syncWithPlayback);
    _syncWithPlayback();
    _startFramePoller();
  }

  @override
  Future<void> dispose() async {
    if (_started) {
      _playbackService.removeListener(_syncWithPlayback);
      _framePoller?.cancel();
      _started = false;
    }
    _ffi?.dispose();
    _ffi = null;
    super.dispose();
  }

  // ── Playback sync ──────────────────────────────────────────────

  void _syncWithPlayback() {
    final ffi = _ffi;
    if (ffi == null) return;

    final state = _playbackService.state;
    final item = state.currentItem;

    if (item == null) {
      ffi.stop();
      _loadedItemId = null;
      return;
    }

    // Load new media if different from current
    if (_loadedItemId != item.id) {
      final videoPath = _pathFor(item.song, MediaAssetType.video);
      final lyricPath = item.song.lyricProject.cachedPath ??
          _pathFor(item.song, MediaAssetType.lyric);
      if (videoPath == null || lyricPath == null) return;
      if (!File(videoPath).existsSync() || !File(lyricPath).existsSync()) {
        return;
      }

      ffi.load(videoPath, lyricPath);
      _loadedItemId = item.id;
    }

    // Sync play/pause
    if (state.isPlaying) {
      ffi.play();
    } else {
      ffi.pause();
    }
  }

  // ── Frame polling ──────────────────────────────────────────────

  Timer? _framePoller;

  void _startFramePoller() {
    _framePoller = Timer.periodic(
      const Duration(milliseconds: 16), // ~60 fps
      (_) => _pollFrame(),
    );
  }

  void _pollFrame() {
    final ffi = _ffi;
    if (ffi == null) return;
    final frame = ffi.readFrame();
    if (frame != null) {
      _latestFrame = frame;
      notifyListeners();
    }

    // Sync position back to PlaybackService
    final pos = ffi.position;
    final dur = ffi.duration;
    // Position sync will be added when PlaybackService supports it
  }

  // ── Helpers ────────────────────────────────────────────────────

  String? _pathFor(Song song, MediaAssetType type) {
    for (final asset in song.assets) {
      if (asset.type != type) continue;
      if (asset.cachedPath != null && asset.cachedPath!.isNotEmpty) {
        return asset.cachedPath;
      }
      if (asset.uri.isScheme('file')) {
        return asset.uri.toFilePath(windows: Platform.isWindows);
      }
    }
    return null;
  }
}
