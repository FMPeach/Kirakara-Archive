import 'dart:ffi';

import 'ime_native_bridge.dart';

class MozcNativeBridgeProbe {
  const MozcNativeBridgeProbe({
    this.libraryName = 'kirakara_mozc.dll',
  });

  final String libraryName;

  NativeImeBridge probe() {
    try {
      final library = DynamicLibrary.open(libraryName);
      return MozcNativeBridge(library: library, libraryName: libraryName);
    } on Object catch (error) {
      return UnavailableNativeImeBridge(
        engineName: 'mozc',
        reason: 'Unable to load $libraryName: $error',
      );
    }
  }
}

class MozcNativeBridge implements NativeImeBridge {
  const MozcNativeBridge({
    required this.library,
    required this.libraryName,
  });

  final DynamicLibrary library;
  final String libraryName;

  @override
  String get engineName => 'mozc';

  @override
  bool get isAvailable => false;

  @override
  String? get unavailableReason {
    return '$libraryName loaded, but Kirakara Mozc ABI bindings are not linked '
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
    throw StateError(unavailableReason ?? 'Mozc bridge is unavailable');
  }

  @override
  Future<NativeImeResult> clear(String sessionId) async {
    throw StateError(unavailableReason ?? 'Mozc bridge is unavailable');
  }
}
