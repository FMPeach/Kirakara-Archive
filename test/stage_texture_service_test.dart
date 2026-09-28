import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kirakara_app/services/stage_texture_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('kirakara/test_stage_texture');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('attaches once per ShowHost and forwards activity changes', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'attach') return 73;
      return true;
    });
    final controller = StageTextureController(textureChannel: channel);

    expect((await controller.attach(1001))?.textureId, 73);
    expect((await controller.attach(1001))?.textureId, 73);
    await controller.setActive(false);
    await controller.setActive(true);

    expect(calls.map((call) => call.method), <String>[
      'attach',
      'setActive',
      'setActive',
    ]);
    expect(calls.first.arguments, <String, Object?>{'hostHandle': 1001});
    expect(calls[1].arguments, <String, Object?>{'active': false});
    expect(calls[2].arguments, <String, Object?>{'active': true});
  });

  test('returns null when the Windows bridge is unavailable', () async {
    final controller = StageTextureController(textureChannel: channel);

    expect(await controller.attach(1001), isNull);
  });

  test('composed backend never registers or wakes an external texture',
      () async {
    const compositorChannel = MethodChannel('kirakara/test_dcomp_stage');
    final textureCalls = <MethodCall>[];
    final compositorCalls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      textureCalls.add(call);
      return 73;
    });
    messenger.setMockMethodCallHandler(compositorChannel, (call) async {
      compositorCalls.add(call);
      switch (call.method) {
        case 'getBackendInfo':
          return <String, Object?>{'backend': 'composed'};
        case 'attachStage':
          return <String, Object?>{
            'backend': 'composed',
            'protocol': 'nt-keyed-latest-v1',
          };
        default:
          return true;
      }
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(compositorChannel, null);
    });

    final controller = StageTextureController(
      textureChannel: channel,
      compositorChannel: compositorChannel,
    );
    final attachment = await controller.attach(1001);
    expect(attachment?.isComposed, isTrue);
    expect(attachment?.textureId, isNull);
    await controller.setComposedGeometry(
      physicalBounds: const Rect.fromLTWH(20, 30, 1280, 720),
    );
    await controller.setComposedGeometry(
      physicalBounds: const Rect.fromLTWH(20, 30, 1280, 720),
    );
    await controller.setActive(true);
    await controller.setActive(false);
    await controller.detach();
    expect((await controller.attach(1001))?.isComposed, isTrue);

    expect(textureCalls, isEmpty);
    expect(compositorCalls.map((call) => call.method), <String>[
      'getBackendInfo',
      'attachStage',
      'setStageGeometry',
      'setStageActive',
      'setStageActive',
      'detachStage',
      'getBackendInfo',
      'attachStage',
    ]);
  });

  test('failed composed geometry remains retryable', () async {
    const compositorChannel = MethodChannel('kirakara/test_dcomp_retry');
    var geometryAttempts = 0;
    messenger.setMockMethodCallHandler(compositorChannel, (call) async {
      switch (call.method) {
        case 'getBackendInfo':
          return <String, Object?>{'backend': 'composed'};
        case 'attachStage':
          return <String, Object?>{'backend': 'composed'};
        case 'setStageGeometry':
          geometryAttempts++;
          if (geometryAttempts == 1) {
            throw PlatformException(code: 'temporary_geometry_failure');
          }
          return true;
        default:
          return true;
      }
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(compositorChannel, null);
    });

    final controller = StageTextureController(
      textureChannel: channel,
      compositorChannel: compositorChannel,
    );
    expect((await controller.attach(1001))?.isComposed, isTrue);
    const bounds = Rect.fromLTWH(20, 30, 1280, 720);
    await controller.setComposedGeometry(physicalBounds: bounds);
    await controller.setComposedGeometry(physicalBounds: bounds);

    expect(geometryAttempts, 2);
  });
}
