import 'dart:io';

import 'package:flutter/services.dart';

class NativeWindowService {
  const NativeWindowService({
    this.channel = const MethodChannel('kirakara/window'),
  });

  final MethodChannel channel;

  Future<int?> getFlutterViewHandle() async {
    if (!Platform.isWindows) return null;
    final handle = await channel.invokeMethod<int>('getFlutterViewHandle');
    if (handle == null || handle == 0) return null;
    return handle;
  }

  Future<List<Map<String, Object?>>> getDisplays() async {
    if (!Platform.isWindows) return const [];
    final raw = await channel.invokeMethod<List<Object?>>('getDisplays');
    if (raw == null) return const [];
    return raw
        .whereType<Map<Object?, Object?>>()
        .map((display) => display.map(
              (key, value) => MapEntry(key.toString(), value),
            ))
        .toList(growable: false);
  }
}
