import 'dart:ffi';

import '../handwriting_stroke.dart';
import 'ime_native_bridge.dart';

abstract class NativeHandwritingBridge {
  String get engineName;
  bool get isAvailable;
  String? get unavailableReason;

  Future<void> activateSession(String sessionId);
  Future<void> deactivateSession(String sessionId);
  Future<List<NativeImeCandidate>> recognize({
    required String sessionId,
    required List<ImeStroke> strokes,
  });
}

class UnavailableNativeHandwritingBridge implements NativeHandwritingBridge {
  const UnavailableNativeHandwritingBridge({
    required this.engineName,
    required this.reason,
  });

  final String reason;

  @override
  final String engineName;

  @override
  bool get isAvailable => false;

  @override
  String? get unavailableReason => reason;

  @override
  Future<void> activateSession(String sessionId) async {}

  @override
  Future<void> deactivateSession(String sessionId) async {}

  @override
  Future<List<NativeImeCandidate>> recognize({
    required String sessionId,
    required List<ImeStroke> strokes,
  }) async {
    throw StateError('$engineName native bridge is unavailable: $reason');
  }
}

class ZinniaNativeBridgeProbe {
  const ZinniaNativeBridgeProbe({
    this.libraryName = 'kirakara_zinnia.dll',
  });

  final String libraryName;

  NativeHandwritingBridge probe() {
    try {
      final library = DynamicLibrary.open(libraryName);
      return ZinniaNativeBridge(library: library, libraryName: libraryName);
    } on Object catch (error) {
      return UnavailableNativeHandwritingBridge(
        engineName: 'zinnia',
        reason: 'Unable to load $libraryName: $error',
      );
    }
  }
}

class ZinniaNativeBridge implements NativeHandwritingBridge {
  const ZinniaNativeBridge({
    required this.library,
    required this.libraryName,
  });

  final DynamicLibrary library;
  final String libraryName;

  @override
  String get engineName => 'zinnia';

  @override
  bool get isAvailable => false;

  @override
  String? get unavailableReason {
    return '$libraryName loaded, but Kirakara Zinnia ABI bindings are not '
        'linked in this Flutter prototype yet';
  }

  @override
  Future<void> activateSession(String sessionId) async {}

  @override
  Future<void> deactivateSession(String sessionId) async {}

  @override
  Future<List<NativeImeCandidate>> recognize({
    required String sessionId,
    required List<ImeStroke> strokes,
  }) async {
    throw StateError(unavailableReason ?? 'Zinnia bridge is unavailable');
  }
}
