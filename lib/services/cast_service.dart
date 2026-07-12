import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'kirakara_show_service.dart';

enum CastState {
  idle,
  searching,
  casting,
}

class CastService extends ChangeNotifier {
  CastState _state = CastState.idle;
  String? _targetName;
  Process? _mpegTsProcess;
  String? _mpegTsUrl;
  String? _lastError;

  CastState get state => _state;
  String? get targetName => _targetName;
  bool get isCasting => _state == CastState.casting;
  String? get mpegTsUrl => _mpegTsUrl;
  String? get lastError => _lastError;

  Future<void> startMockCast({String targetName = '客厅电视'}) async {
    _state = CastState.searching;
    notifyListeners();
    await Future<void>.delayed(const Duration(milliseconds: 350));
    _targetName = targetName;
    _state = CastState.casting;
    notifyListeners();
  }

  Future<void> startMpegTsDebugStream(
    KirakaraShowService showService, {
    int rawInputPort = 17391,
    int httpPort = 7392,
  }) async {
    await stopCast(showService: showService);

    final ffmpeg = _findFfmpeg();
    if (ffmpeg == null) {
      const message = '未找到 ffmpeg.exe';
      _lastError = message;
      notifyListeners();
      throw StateError(message);
    }

    _state = CastState.searching;
    _targetName = 'MPEG-TS 初始化中';
    _mpegTsUrl = 'http://127.0.0.1:$httpPort/cast/stage.ts';
    _lastError = null;
    notifyListeners();

    final args = <String>[
      '-hide_banner',
      '-loglevel',
      'warning',
      '-fflags',
      'nobuffer',
      '-flags',
      'low_delay',
      '-f',
      'rawvideo',
      '-pixel_format',
      'bgra',
      '-video_size',
      '1920x1080',
      '-framerate',
      '60',
      '-i',
      'tcp://127.0.0.1:$rawInputPort?listen=1',
      '-an',
      '-c:v',
      'libx264',
      '-preset',
      'ultrafast',
      '-tune',
      'zerolatency',
      '-pix_fmt',
      'yuv420p',
      '-g',
      '60',
      '-keyint_min',
      '60',
      '-sc_threshold',
      '0',
      '-f',
      'mpegts',
      '-listen',
      '1',
      'http://0.0.0.0:$httpPort/cast/stage.ts',
    ];

    late final Process process;
    try {
      process = await Process.start(ffmpeg, args);
    } catch (error) {
      _targetName = null;
      _mpegTsUrl = null;
      _state = CastState.idle;
      _lastError = 'ffmpeg 启动失败：$error';
      notifyListeners();
      rethrow;
    }
    _mpegTsProcess = process;
    _pipeFfmpegLogs(process);
    unawaited(_watchFfmpegExit(process));

    var connected = false;
    for (var i = 0; i < 12; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      connected = showService.startCastStream(rawInputPort);
      if (connected) break;
    }

    if (!connected) {
      await stopCast(showService: showService);
      const message = '无法连接 ffmpeg rawvideo 输入端口';
      _lastError = message;
      notifyListeners();
      throw StateError(message);
    }

    _targetName = 'MPEG-TS · $_mpegTsUrl';
    _state = CastState.casting;
    notifyListeners();
  }

  Future<void> stopCast({KirakaraShowService? showService}) async {
    showService?.stopCastStream();
    final process = _mpegTsProcess;
    _mpegTsProcess = null;
    if (process != null) {
      process.kill();
      try {
        await process.exitCode.timeout(const Duration(seconds: 2));
      } on TimeoutException {
        // Process.kill on Windows can lag if ffmpeg is inside socket teardown.
      }
    }
    _targetName = null;
    _mpegTsUrl = null;
    _state = CastState.idle;
    notifyListeners();
  }

  @override
  void dispose() {
    final process = _mpegTsProcess;
    _mpegTsProcess = null;
    process?.kill();
    super.dispose();
  }

  void _pipeFfmpegLogs(Process process) {
    void capture(String text) {
      final trimmed = text.trim();
      if (trimmed.isEmpty) return;
      _lastError = trimmed.split('\n').last.trim();
      debugPrint('ffmpeg MPEG-TS: $_lastError');
      notifyListeners();
    }

    process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(capture);
    process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(capture);
  }

  Future<void> _watchFfmpegExit(Process process) async {
    final code = await process.exitCode;
    if (!identical(_mpegTsProcess, process)) return;
    _mpegTsProcess = null;
    _lastError = 'ffmpeg 已退出：$code';
    _targetName = null;
    _mpegTsUrl = null;
    _state = CastState.idle;
    notifyListeners();
  }

  static String? _findFfmpeg() {
    const bundled = r'D:\Program Files\ffmpeg\bin\ffmpeg.exe';
    if (File(bundled).existsSync()) return bundled;

    final path = Platform.environment['PATH'];
    if (path == null || path.isEmpty) return null;
    for (final dir in path.split(';')) {
      final trimmed = dir.trim();
      if (trimmed.isEmpty) continue;
      final candidate = '$trimmed\\ffmpeg.exe';
      if (File(candidate).existsSync()) return candidate;
    }
    return null;
  }
}
