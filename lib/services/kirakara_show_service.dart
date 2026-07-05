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
  String? _lastCompletedItemId;
  bool _sawEngineProgressForItem = false;
  bool _started = false;
  bool _applyingEnginePosition = false;
  bool _controllerPreviewSuppressed = false;
  Duration _enginePosition = Duration.zero;
  Duration _engineDuration = Duration.zero;

  /// The engine's render surface dimensions.
  int get engineWidth => _ffi?.width ?? 0;
  int get engineHeight => _ffi?.height ?? 0;
  Duration get enginePosition => _enginePosition;
  Duration get engineDuration => _engineDuration;
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
      _lastCompletedItemId = null;
      _sawEngineProgressForItem = false;
      _enginePosition = Duration.zero;
      _engineDuration = Duration.zero;
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
      _lastCompletedItemId = null;
      _sawEngineProgressForItem = false;
      _enginePosition = Duration.zero;
      _engineDuration = Duration.zero;
    }

    if (_loadedAudioTrackMode != state.audioTrackMode) {
      final changed = ffi.setAudioTrack(_trackIndex(state.audioTrackMode));
      if (changed) {
        _loadedAudioTrackMode = state.audioTrackMode;
      }
    }

    _syncRequestedPosition(ffi, state);

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
    final duration = ffi.duration;
    final engineState = ffi.state;
    if (pos.isFinite && pos >= 0) {
      _enginePosition = Duration(milliseconds: (pos * 1000).round());
    }
    if (duration.isFinite && duration > 0) {
      _engineDuration = Duration(milliseconds: (duration * 1000).round());
    }

    final state = _playbackService.state;
    final itemId = state.currentItem?.id;
    if (state.isPlaying &&
        itemId != null &&
        itemId == _loadedItemId &&
        (engineState == 1 ||
            _enginePosition > const Duration(milliseconds: 1000))) {
      _sawEngineProgressForItem = true;
    }
    if (_shouldAdvanceAfterEngineEnd(
      state: state,
      itemId: itemId,
      engineState: engineState,
    )) {
      _advanceAfterEngineEnd(itemId!);
      return;
    }

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

  void _syncRequestedPosition(
    KirakaraShowFFI ffi,
    PlaybackState state,
  ) {
    if (state.currentSong == null) return;

    final rawPosition = ffi.position;
    if (!rawPosition.isFinite || rawPosition < 0) return;

    final enginePosition = Duration(
      milliseconds: (rawPosition * 1000).round(),
    );
    final requestedPosition =
        state.position < Duration.zero ? Duration.zero : state.position;
    final diffMs = (requestedPosition - enginePosition).inMilliseconds.abs();
    if (diffMs < 500) return;

    ffi.seek(requestedPosition.inMilliseconds / 1000.0);
    _enginePosition = requestedPosition;
    _lastCompletedItemId = null;
    _sawEngineProgressForItem = false;
  }

  bool _shouldAdvanceAfterEngineEnd({
    required PlaybackState state,
    required String? itemId,
    required int engineState,
  }) {
    if (!state.isPlaying || itemId == null || itemId != _loadedItemId) {
      return false;
    }
    if (_lastCompletedItemId == itemId) return false;

    const stopped = 3;
    if (engineState == stopped && _sawEngineProgressForItem) return true;

    if (_engineDuration <= Duration.zero) return false;
    if (_enginePosition < const Duration(seconds: 1)) return false;
    return _enginePosition + const Duration(milliseconds: 450) >=
        _engineDuration;
  }

  void _advanceAfterEngineEnd(String itemId) {
    _lastCompletedItemId = itemId;
    _applyingEnginePosition = true;
    try {
      _playbackService.next();
    } finally {
      _applyingEnginePosition = false;
    }
    _syncWithPlayback();
  }
}
