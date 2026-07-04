import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../domain/media_asset.dart';
import '../domain/playback_state.dart';
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
  AudioTrackMode? _loadedAudioTrackMode;
  bool? _lastPlaying;
  bool _started = false;
  bool _applyingEnginePosition = false;
  bool _controllerPreviewSuppressed = false;

  /// The engine's render surface dimensions.
  int get engineWidth => _ffi?.width ?? 0;
  int get engineHeight => _ffi?.height ?? 0;
  bool get controllerPreviewSuppressed => _controllerPreviewSuppressed;

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
    if (_applyingEnginePosition) return;
    final ffi = _ffi;
    if (ffi == null) return;

    final state = _playbackService.state;
    final item = state.currentItem;

    if (item == null) {
      ffi.stop();
      _loadedItemId = null;
      _loadedAudioTrackMode = null;
      _lastPlaying = null;
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
      final vocalPath = _existingPathFor(item.song, MediaAssetType.vocal);
      final accompanimentPath =
          _existingPathFor(item.song, MediaAssetType.accompaniment);

      final loaded = ffi.load(
        videoPath,
        lyricPath,
        vocalPath: vocalPath,
        accompanimentPath: accompanimentPath,
      );
      if (!loaded) return;
      _loadedItemId = item.id;
      _loadedAudioTrackMode = vocalPath == null && accompanimentPath != null
          ? AudioTrackMode.accompaniment
          : AudioTrackMode.vocal;
      _lastPlaying = null;
    }

    if (_loadedAudioTrackMode != state.audioTrackMode) {
      final changed = ffi.setAudioTrack(_trackIndex(state.audioTrackMode));
      if (changed) {
        _loadedAudioTrackMode = state.audioTrackMode;
      }
    }

    // Sync play/pause
    if (_lastPlaying == state.isPlaying) return;
    if (state.isPlaying) {
      ffi.play();
    } else {
      ffi.pause();
    }
    _lastPlaying = state.isPlaying;
  }

  // ── Frame polling ──────────────────────────────────────────────

  Timer? _framePoller;

  void _startFramePoller() {
    _framePoller = Timer.periodic(
      const Duration(milliseconds: 33),
      (_) => _pollFrame(),
    );
  }

  void _pollFrame() {
    final ffi = _ffi;
    if (ffi == null) return;

    final pos = ffi.position;
    if (pos.isFinite) {
      final beforeItemId = _playbackService.state.currentItem?.id;
      _applyingEnginePosition = true;
      final bool changed;
      try {
        changed = _playbackService.syncEnginePosition(
          Duration(milliseconds: (pos * 1000).round()),
        );
      } finally {
        _applyingEnginePosition = false;
      }
      final afterItemId = _playbackService.state.currentItem?.id;
      if (changed && beforeItemId != afterItemId) {
        _syncWithPlayback();
      }
    }
  }

  void setStageWindowVisible(bool visible) {
    _ffi?.setStageVisible(visible);
  }

  void setControllerPreviewRect({
    required int parentHwnd,
    required int x,
    required int y,
    required int width,
    required int height,
  }) {
    _ffi?.setControllerPreviewRect(
      parentHwnd: parentHwnd,
      x: x,
      y: y,
      width: width,
      height: height,
    );
  }

  void hideControllerPreview() {
    _ffi?.hideControllerPreview();
  }

  void setControllerPreviewSuppressed(bool suppressed) {
    if (_controllerPreviewSuppressed == suppressed) return;
    _controllerPreviewSuppressed = suppressed;
    if (suppressed) {
      _ffi?.setControllerQrRect(
        visible: false,
        x: 0,
        y: 0,
        size: 0,
      );
      _ffi?.hideControllerPreview();
    }
    notifyListeners();
  }

  void setControllerQrRect({
    required bool visible,
    required int x,
    required int y,
    required int size,
  }) {
    _ffi?.setControllerQrRect(
      visible: visible,
      x: x,
      y: y,
      size: size,
    );
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

  String? _existingPathFor(Song song, MediaAssetType type) {
    final path = _pathFor(song, type);
    if (path == null || !File(path).existsSync()) return null;
    return path;
  }

  int _trackIndex(AudioTrackMode mode) {
    return mode == AudioTrackMode.accompaniment ? 1 : 0;
  }
}
