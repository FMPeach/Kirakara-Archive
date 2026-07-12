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
  HttpServer? _mpegTsHttpServer;
  StreamSubscription<List<int>>? _ffmpegStdoutSub;
  StreamSubscription<String>? _ffmpegStderrSub;
  final Set<HttpResponse> _mpegTsClients = <HttpResponse>{};
  KirakaraShowService? _activeShowService;
  String? _mpegTsUrl;
  int _mpegTsRawInputPort = 17391;
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
    _mpegTsRawInputPort = rawInputPort;
    _mpegTsUrl = 'http://127.0.0.1:$httpPort/cast/stage.ts';
    _lastError = null;
    notifyListeners();

    await _killOrphanFfmpegs(rawInputPort);
    try {
      await _startMpegTsHttpServer(httpPort);
    } catch (error) {
      _targetName = null;
      _mpegTsUrl = null;
      _state = CastState.idle;
      _lastError = 'MPEG-TS HTTP 服务启动失败：$error';
      notifyListeners();
      rethrow;
    }

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
      '-flush_packets',
      '1',
      '-muxdelay',
      '0',
      '-muxpreload',
      '0',
      '-f',
      'mpegts',
      'pipe:1',
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
    _activeShowService = showService;
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
    (showService ?? _activeShowService)?.stopCastStream();
    _activeShowService = null;
    final process = _mpegTsProcess;
    _mpegTsProcess = null;
    if (process != null) {
      process.kill();
      try {
        await process.exitCode.timeout(const Duration(seconds: 2));
      } on TimeoutException {
        // Process.kill on Windows can lag.
      }
    }
    await _stopMpegTsHttpServer();
    // Kill any orphaned ffmpeg instances that might hold our ports.
    await _killOrphanFfmpegs(_mpegTsRawInputPort);
    _targetName = null;
    _mpegTsUrl = null;
    _state = CastState.idle;
    notifyListeners();
  }

  /// Kill any ffmpeg.exe processes listening on our raw BGRA input port.
  static Future<void> _killOrphanFfmpegs(int rawInputPort) async {
    try {
      final result = await Process.run('netstat', ['-ano']);
      final lines = result.stdout.toString().split('\n');
      final pids = <int>{};
      for (final line in lines) {
        if (!line.contains(':$rawInputPort') || !line.contains('LISTENING')) {
          continue;
        }
        final parts = line.trim().split(RegExp(r'\s+'));
        final pid = int.tryParse(parts.last);
        if (pid != null && pid > 0) pids.add(pid);
      }
      for (final pid in pids) {
        try {
          final taskResult = await Process.run(
            'tasklist', ['/FI', 'PID eq $pid', '/FO', 'CSV', '/NH']);
          if (taskResult.stdout.toString().contains('ffmpeg.exe')) {
            Process.killPid(pid);
            debugPrint('CastService: killed orphaned ffmpeg PID $pid');
          }
        } catch (_) {}
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    final process = _mpegTsProcess;
    _mpegTsProcess = null;
    process?.kill();
    _mpegTsHttpServer?.close(force: true);
    for (final client in List<HttpResponse>.of(_mpegTsClients)) {
      client.close();
    }
    _mpegTsClients.clear();
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

    _ffmpegStdoutSub = process.stdout.listen(_broadcastMpegTsChunk);
    _ffmpegStderrSub = process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(capture);
  }

  Future<void> _watchFfmpegExit(Process process) async {
    final code = await process.exitCode;
    if (!identical(_mpegTsProcess, process)) return;
    _mpegTsProcess = null;
    _activeShowService?.stopCastStream();
    _activeShowService = null;
    await _stopMpegTsHttpServer();
    _lastError = 'ffmpeg 已退出：$code';
    _targetName = null;
    _mpegTsUrl = null;
    _state = CastState.idle;
    notifyListeners();
  }

  Future<void> _startMpegTsHttpServer(int httpPort) async {
    final server = await HttpServer.bind(InternetAddress.anyIPv4, httpPort);
    _mpegTsHttpServer = server;
    unawaited(_serveMpegTsHttp(server));
  }

  Future<void> _serveMpegTsHttp(HttpServer server) async {
    try {
      await for (final request in server) {
        if (request.method != 'GET' || request.uri.path != '/cast/stage.ts') {
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
          continue;
        }

        final response = request.response;
        response.headers.contentType = ContentType('video', 'MP2T');
        response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
        response.headers.chunkedTransferEncoding = true;
        _mpegTsClients.add(response);
        unawaited(response.done.whenComplete(() {
          _mpegTsClients.remove(response);
        }));
      }
    } catch (_) {
      // Closing the server during cast shutdown can end the request stream.
    }
  }

  Future<void> _stopMpegTsHttpServer() async {
    await _ffmpegStdoutSub?.cancel();
    await _ffmpegStderrSub?.cancel();
    _ffmpegStdoutSub = null;
    _ffmpegStderrSub = null;

    final server = _mpegTsHttpServer;
    _mpegTsHttpServer = null;
    if (server != null) {
      await server.close(force: true);
    }
    for (final client in List<HttpResponse>.of(_mpegTsClients)) {
      await client.close();
    }
    _mpegTsClients.clear();
  }

  void _broadcastMpegTsChunk(List<int> chunk) {
    if (_mpegTsClients.isEmpty) return;
    for (final client in List<HttpResponse>.of(_mpegTsClients)) {
      try {
        client.add(chunk);
      } catch (_) {
        _mpegTsClients.remove(client);
        unawaited(client.close());
      }
    }
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
