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
    final controller = StageTextureController(channel: channel);

    expect(await controller.attach(1001), 73);
    expect(await controller.attach(1001), 73);
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
    final controller = StageTextureController(channel: channel);

    expect(await controller.attach(1001), isNull);
  });
}
