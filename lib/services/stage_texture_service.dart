import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class StageTextureStats {
  const StageTextureStats({
    required this.publishedFrames,
    required this.acquiredFrames,
  });

  final int publishedFrames;
  final int acquiredFrames;
}

class StageTextureController {
  StageTextureController({
    MethodChannel channel = const MethodChannel('kirakara/stage_texture'),
  }) : _channel = channel;

  final MethodChannel _channel;
  int? _hostHandle;
  int? _textureId;
  Future<int?>? _pendingAttach;

  int? get textureId => _textureId;

  Future<int?> attach(int hostHandle) {
    if (hostHandle == 0) return Future<int?>.value(null);
    if (_hostHandle == hostHandle && _textureId != null) {
      return Future<int?>.value(_textureId);
    }
    final pending = _pendingAttach;
    if (_hostHandle == hostHandle && pending != null) return pending;

    _hostHandle = hostHandle;
    final future = _attach(hostHandle);
    _pendingAttach = future;
    return future;
  }

  Future<int?> _attach(int hostHandle) async {
    try {
      final textureId = await _channel.invokeMethod<int>(
        'attach',
        <String, Object?>{'hostHandle': hostHandle},
      );
      if (_hostHandle == hostHandle) _textureId = textureId;
      return textureId;
    } on MissingPluginException catch (error) {
      debugPrint('Unified Stage texture bridge is unavailable: $error');
      return null;
    } on PlatformException catch (error) {
      debugPrint('Unified Stage texture unavailable: ${error.message}');
      return null;
    } finally {
      if (_hostHandle == hostHandle) _pendingAttach = null;
    }
  }

  Future<void> setActive(bool active) async {
    if (_textureId == null) return;
    try {
      await _channel.invokeMethod<void>(
        'setActive',
        <String, Object?>{'active': active},
      );
    } on MissingPluginException catch (error) {
      debugPrint('Unified Stage texture bridge is unavailable: $error');
    } on PlatformException catch (error) {
      debugPrint('Unable to update Stage texture activity: ${error.message}');
    }
  }

  Future<StageTextureStats?> readStats() async {
    if (_textureId == null) return null;
    try {
      final result = await _channel.invokeMapMethod<String, Object?>(
        'getStats',
      );
      if (result == null) return null;
      return StageTextureStats(
        publishedFrames: (result['publishedFrames'] as num?)?.toInt() ?? 0,
        acquiredFrames: (result['acquiredFrames'] as num?)?.toInt() ?? 0,
      );
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }
}
