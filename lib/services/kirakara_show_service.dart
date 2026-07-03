import 'dart:async';
import 'dart:io';

import '../domain/media_asset.dart';
import '../domain/song.dart';
import 'playback_service.dart';

class KirakaraShowService {
  KirakaraShowService({
    required PlaybackService playbackService,
    this.executablePath =
        r'D:\仓库\Kirakara Show\build\bin\kirakara_video_demo.exe',
    this.workingDirectory = r'D:\仓库\Kirakara Show',
  }) : _playbackService = playbackService;

  final PlaybackService _playbackService;
  final String executablePath;
  final String workingDirectory;

  Process? _process;
  String? _runningItemId;
  String? _launchingItemId;
  bool _started = false;

  void start() {
    if (_started) return;
    _started = true;
    _playbackService.addListener(_syncWithPlayback);
    _syncWithPlayback();
  }

  Future<void> dispose() async {
    if (_started) {
      _playbackService.removeListener(_syncWithPlayback);
      _started = false;
    }
    await stop();
  }

  Future<void> stop({bool preserveLaunching = false}) async {
    final process = _process;
    _process = null;
    _runningItemId = null;
    if (!preserveLaunching) {
      _launchingItemId = null;
    }
    if (process == null) return;
    process.kill();
    try {
      await process.exitCode.timeout(const Duration(seconds: 1));
    } on TimeoutException {
      if (Platform.isWindows) {
        await Process.run('taskkill', [
          '/PID',
          process.pid.toString(),
          '/T',
          '/F',
        ]);
        try {
          await process.exitCode.timeout(const Duration(seconds: 2));
        } on TimeoutException {
          // Continue launching the next stage rather than freezing controller
          // playback if Windows still refuses to tear the demo window down.
        }
      }
    }
  }

  void _syncWithPlayback() {
    final state = _playbackService.state;
    final item = state.currentItem;
    if (item == null || !state.isPlaying) {
      return;
    }

    if (_runningItemId == item.id && _process != null) {
      return;
    }
    if (_launchingItemId == item.id) {
      return;
    }

    unawaited(_launch(item.id, item.song));
  }

  Future<void> _launch(String itemId, Song song) async {
    _launchingItemId = itemId;
    final videoPath = _pathFor(song, MediaAssetType.video);
    final lyricPath =
        song.lyricProject.cachedPath ?? _pathFor(song, MediaAssetType.lyric);
    if (videoPath == null || lyricPath == null) {
      _clearLaunching(itemId);
      return;
    }
    if (!File(executablePath).existsSync() ||
        !File(videoPath).existsSync() ||
        !File(lyricPath).existsSync()) {
      _clearLaunching(itemId);
      return;
    }

    try {
      await stop(preserveLaunching: true);
      _launchingItemId = itemId;
      final process = await Process.start(
        executablePath,
        [videoPath, lyricPath],
        workingDirectory:
            Directory(workingDirectory).existsSync() ? workingDirectory : null,
        mode: ProcessStartMode.normal,
      );
      _process = process;
      _runningItemId = itemId;
      unawaited(process.exitCode.then((_) {
        if (identical(_process, process)) {
          _process = null;
          _runningItemId = null;
        }
      }));
    } finally {
      _clearLaunching(itemId);
    }
  }

  void _clearLaunching(String itemId) {
    if (_launchingItemId == itemId) {
      _launchingItemId = null;
    }
  }

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
