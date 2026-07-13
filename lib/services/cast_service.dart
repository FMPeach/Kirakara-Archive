import 'dart:async';

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
  KirakaraShowService? _activeShowService;
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
    KirakaraShowService showService,
  ) async {
    await stopCast(showService: showService);

    _state = CastState.searching;
    _targetName = 'MPEG-TS 初始化中';
    _mpegTsUrl = null;
    _lastError = null;
    notifyListeners();

    final started = showService.startCastStream(0);
    final port = started ? showService.castStreamPort : 0;
    if (!started || port == 0) {
      showService.stopCastStream();
      const message = '当前设备无法启动原生 Stage 编码或 HTTP 服务';
      _targetName = null;
      _state = CastState.idle;
      _lastError = message;
      notifyListeners();
      throw StateError(message);
    }

    _activeShowService = showService;
    _mpegTsUrl = 'http://127.0.0.1:$port/cast/stage.ts';
    _targetName = 'MPEG-TS · $_mpegTsUrl';
    _state = CastState.casting;
    notifyListeners();
  }

  Future<void> stopCast({KirakaraShowService? showService}) async {
    (showService ?? _activeShowService)?.stopCastStream();
    _activeShowService = null;
    _targetName = null;
    _mpegTsUrl = null;
    _lastError = null;
    _state = CastState.idle;
    notifyListeners();
  }

  @override
  void dispose() {
    _activeShowService?.stopCastStream();
    _activeShowService = null;
    super.dispose();
  }
}
