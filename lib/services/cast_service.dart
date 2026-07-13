import 'dart:async';

import 'package:flutter/foundation.dart';

import 'dlna/dlna_control_point.dart';
import 'dlna/dlna_device.dart';
import 'dlna/dlna_discovery_service.dart';
import 'kirakara_show_service.dart';
import 'lan_address_resolver.dart';

enum CastState {
  idle,
  searching,
  casting,
}

class CastService extends ChangeNotifier {
  CastService({
    DlnaDiscoveryService? discoveryService,
    DlnaControlPoint? controlPoint,
  })  : _discoveryService = discoveryService ?? DlnaDiscoveryService(),
        _controlPoint = controlPoint ?? const DlnaControlPoint();

  final DlnaDiscoveryService _discoveryService;
  final DlnaControlPoint _controlPoint;

  bool _isEnabled = false;
  bool _isDiscovering = false;
  CastState _state = CastState.idle;
  List<DlnaDevice> _devices = const [];
  DlnaDevice? _activeDevice;
  String? _targetName;
  KirakaraShowService? _activeShowService;
  String? _mpegTsUrl;
  String? _lastError;
  int _discoveryGeneration = 0;
  int _sessionGeneration = 0;

  bool get isEnabled => _isEnabled;
  bool get isDiscovering => _isDiscovering;
  CastState get state => _state;
  List<DlnaDevice> get devices => List.unmodifiable(_devices);
  DlnaDevice? get activeDevice => _activeDevice;
  String? get targetName => _targetName;
  bool get isCasting => _state == CastState.casting;
  String? get mpegTsUrl => _mpegTsUrl;
  String? get lastError => _lastError;

  Future<void> enableCastMode() async {
    if (!_isEnabled) {
      _isEnabled = true;
      _lastError = null;
      notifyListeners();
    }
    await refreshDevices();
  }

  Future<void> disableCastMode({
    KirakaraShowService? showService,
  }) async {
    _isEnabled = false;
    _discoveryGeneration++;
    _isDiscovering = false;
    await stopCast(showService: showService);
    _devices = const [];
    notifyListeners();
  }

  Future<void> refreshDevices() async {
    if (!_isEnabled || _isDiscovering) return;
    final generation = ++_discoveryGeneration;
    _isDiscovering = true;
    _lastError = null;
    notifyListeners();
    try {
      final devices = await _discoveryService.discover();
      if (!_isEnabled || generation != _discoveryGeneration) return;
      _devices = devices;
    } catch (error) {
      if (!_isEnabled || generation != _discoveryGeneration) return;
      _devices = const [];
      _lastError = error.toString();
    } finally {
      if (_isEnabled && generation == _discoveryGeneration) {
        _isDiscovering = false;
        notifyListeners();
      }
    }
  }

  Future<void> connectToDevice(
    DlnaDevice device,
    KirakaraShowService showService,
  ) async {
    if (_state == CastState.searching) return;
    if (_activeDevice?.id == device.id && isCasting) {
      await stopCast(showService: showService);
      return;
    }

    _isEnabled = true;
    await stopCast(showService: showService);
    final generation = ++_sessionGeneration;
    _activeDevice = device;
    _targetName = device.friendlyName;
    _mpegTsUrl = null;
    _lastError = null;
    _state = CastState.searching;
    notifyListeners();

    try {
      final streamUri = _startNativeStream(
        showService,
        localAddress: device.localAddress,
      );
      _activeShowService = showService;
      _mpegTsUrl = streamUri.toString();

      await _controlPoint.setTransportUriAndPlay(
        device,
        streamUri,
        title: 'Kira Karaoke',
      );
      if (generation != _sessionGeneration) return;
      _state = CastState.casting;
      notifyListeners();
    } catch (error) {
      if (generation != _sessionGeneration) return;
      showService.stopCastStream();
      _activeShowService = null;
      _activeDevice = null;
      _targetName = null;
      _mpegTsUrl = null;
      _state = CastState.idle;
      _lastError = error.toString();
      notifyListeners();
      rethrow;
    }
  }

  /// Keeps the existing raw stream test available for development tools.
  Future<void> startMpegTsDebugStream(
    KirakaraShowService showService,
  ) async {
    _isEnabled = true;
    await stopCast(showService: showService);
    _state = CastState.searching;
    _targetName = 'VLC 测试输出';
    _lastError = null;
    notifyListeners();
    try {
      final lanIp = await LanAddressResolver.detectIpv4();
      if (lanIp == null) {
        throw StateError('未找到可用的实体局域网 IPv4，请检查 Wi-Fi 或网线连接');
      }
      final streamUri = _startNativeStream(
        showService,
        localAddress: lanIp,
      );
      _activeShowService = showService;
      _mpegTsUrl = streamUri.toString();
      _state = CastState.casting;
      notifyListeners();
    } catch (error) {
      showService.stopCastStream();
      _activeShowService = null;
      _targetName = null;
      _mpegTsUrl = null;
      _state = CastState.idle;
      _lastError = error.toString();
      notifyListeners();
      rethrow;
    }
  }

  Future<void> stopCast({KirakaraShowService? showService}) async {
    _sessionGeneration++;
    final device = _activeDevice;
    if (device != null) {
      try {
        await _controlPoint.stop(device).timeout(const Duration(seconds: 3));
      } catch (_) {
        // The renderer may already be offline; local cleanup must still run.
      }
    }
    (showService ?? _activeShowService)?.stopCastStream();
    _activeShowService = null;
    _activeDevice = null;
    _targetName = null;
    _mpegTsUrl = null;
    _lastError = null;
    _state = CastState.idle;
    notifyListeners();
  }

  Uri _startNativeStream(
    KirakaraShowService showService, {
    required String localAddress,
  }) {
    final started = showService.startCastStream(0);
    final port = started ? showService.castStreamPort : 0;
    if (!started || port == 0) {
      showService.stopCastStream();
      throw StateError('当前设备无法启动投屏编码或局域网输出服务');
    }
    return Uri.parse('http://$localAddress:$port/cast/stage.ts');
  }

  @override
  void dispose() {
    _discoveryGeneration++;
    _sessionGeneration++;
    _activeShowService?.stopCastStream();
    _activeShowService = null;
    super.dispose();
  }
}
