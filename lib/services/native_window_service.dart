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
}
