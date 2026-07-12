import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'kirakara_show_service.dart';

enum CastState { idle, starting, casting }

class CastService extends ChangeNotifier {
  CastService({required KirakaraShowService showService})
      : _showService = showService;

  final KirakaraShowService _showService;
  CastState _state = CastState.idle;
  Process? _ffmpeg;
  bool _explicitStop = false;

  static const _ffmpegInPort = 12953;
  static const _httpPort = 12952;
  static const _videoWidth = 1920;
  static const _videoHeight = 1080;

  CastState get state => _state;
  bool get isCasting => _state == CastState.casting;

  Future<void> startCast() async {
    if (_state != CastState.idle) return;
    _state = CastState.starting;
    _explicitStop = false;
    notifyListeners();

    try {
      // Launch ffmpeg: listen on TCP for raw BGRA, serve MPEG-TS over HTTP.
      _ffmpeg = await Process.start('ffmpeg', [
        '-f', 'rawvideo',
        '-pix_fmt', 'bgra',
        '-s', '${_videoWidth}x$_videoHeight',
        '-r', '60',
        '-i', 'tcp://127.0.0.1:$_ffmpegInPort?listen',
        '-c:v', 'libx264',
        '-preset', 'veryfast',
        '-tune', 'zerolatency',
        '-crf', '23',
        '-g', '60',
        '-pix_fmt', 'yuv420p',
        '-f', 'mpegts',
        '-listen', '1',
        'http://0.0.0.0:$_httpPort/live.ts',
      ], mode: ProcessStartMode.detached);

      // Give ffmpeg a moment to bind.
      await Future<void>.delayed(const Duration(milliseconds: 500));

      // Tell the engine to start streaming frames to ffmpeg.
      final ok = _showService.startCastStream(_ffmpegInPort);
      if (ok) {
        _showService.setControllerPreviewSuppressed(true);
        _state = CastState.casting;
        debugPrint('CastService: streaming on http://0.0.0.0:$_httpPort/live.ts');
      } else {
        debugPrint('CastService: engine refused cast stream');
        _state = CastState.idle;
        _killFfmpeg();
      }
    } catch (e) {
      debugPrint('CastService: failed to start: $e');
      _state = CastState.idle;
      _killFfmpeg();
      // Monitor ffmpeg exit and auto-stop.
      _monitorFfmpeg();
    }
    notifyListeners();
  }

  Future<void> stopCast() async {
    _explicitStop = true;
    _showService.stopCastStream();
    _showService.setControllerPreviewSuppressed(false);
    _killFfmpeg();
    _state = CastState.idle;
    notifyListeners();
  }

  void _killFfmpeg() {
    _ffmpeg?.kill(ProcessSignal.sigterm);
    _ffmpeg = null;
  }

  void _monitorFfmpeg() {
    final proc = _ffmpeg;
    if (proc == null) return;
    unawaited(proc.exitCode.then((code) {
      if (!_explicitStop && _state == CastState.casting) {
        debugPrint('CastService: ffmpeg exited with code $code');
        _showService.stopCastStream();
        _showService.setControllerPreviewSuppressed(false);
        _state = CastState.idle;
        _ffmpeg = null;
        notifyListeners();
      }
    }));
  }

  @override
  Future<void> dispose() async {
    stopCast();
    super.dispose();
  }
}
