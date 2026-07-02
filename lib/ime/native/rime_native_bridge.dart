import 'dart:ffi';

import 'ime_native_bridge.dart';

class RimeNativeBridgeProbe {
  const RimeNativeBridgeProbe({
    this.libraryName = 'kirakara_rime.dll',
  });

  final String libraryName;

  NativeImeBridge probe() {
    try {
      final library = DynamicLibrary.open(libraryName);
      return RimeNativeBridge(library: library, libraryName: libraryName);
    } on Object catch (error) {
      return UnavailableNativeImeBridge(
        engineName: 'rime',
        reason: 'Unable to load $libraryName: $error',
      );
    }
  }
}

class RimeNativeBridge implements NativeImeBridge {
  const RimeNativeBridge({
    required this.library,
    required this.libraryName,
  });

  final DynamicLibrary library;
  final String libraryName;

  @override
  String get engineName => 'rime';

  @override
  bool get isAvailable => false;

  @override
  String? get unavailableReason {
    return '$libraryName loaded, but Kirakara Rime ABI bindings are not linked '
        'in this Flutter prototype yet';
  }

  @override
  Future<void> activateSession(String sessionId) async {}

  @override
  Future<void> deactivateSession(String sessionId) async {}

  @override
  Future<NativeImeResult> compose({
    required String sessionId,
    required String rawInput,
    required int pageIndex,
  }) async {
    throw StateError(unavailableReason ?? 'Rime bridge is unavailable');
  }

  @override
  Future<NativeImeResult> clear(String sessionId) async {
    throw StateError(unavailableReason ?? 'Rime bridge is unavailable');
  }
}
