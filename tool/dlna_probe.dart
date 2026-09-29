import 'dart:io';

import 'package:kirakara_app/services/dlna/dlna_control_point.dart';
import 'package:kirakara_app/services/dlna/dlna_device.dart';
import 'package:kirakara_app/services/dlna/dlna_discovery_service.dart';

Future<void> main(List<String> args) async {
  try {
    await _run(args);
  } catch (error) {
    stderr.writeln('DLNA probe failed: $error');
    exitCode = 1;
  }
}

Future<void> _run(List<String> args) async {
  final discovery = DlnaDiscoveryService(logger: stdout.writeln);
  const controlPoint = DlnaControlPoint();

  late final List<DlnaDevice> devices;
  if (args.length == 1 && args.single == '--purek') {
    stdout.writeln(
      '正在扫描 192.168.254.1-254:49152 的 Pure K MediaRenderer...',
    );
    devices = await discovery.discoverPureKRenderers();
  } else if (args.isEmpty) {
    stdout.writeln('正在扫描实体局域网内的 DLNA MediaRenderer...');
    devices = await discovery.discover(
      responseWindow: const Duration(seconds: 4),
    );
  } else {
    final input = args.join(' ').trim();
    stdout.writeln('正在解析手动 DLNA Renderer：$input');
    devices = [await discovery.resolveManualRenderer(input)];
  }
  if (devices.isEmpty) {
    stdout.writeln('未发现设备。');
    return;
  }

  for (final device in devices) {
    stdout.writeln('${device.friendlyName} (${device.detailLabel})');
    stdout.writeln('  LOCATION: ${device.location}');
    stdout.writeln('  UDN: ${device.udn.isEmpty ? '未声明' : device.udn}');
    stdout.writeln('  AVTransport: ${device.avTransport.controlUrl}');
    stdout.writeln(
      '  RenderingControl: '
      '${device.renderingControl?.controlUrl ?? '未声明'}',
    );
    stdout.writeln(
      '  ConnectionManager: '
      '${device.connectionManager?.controlUrl ?? '未声明'}',
    );
    try {
      final protocols = await controlPoint.getSinkProtocolInfo(device);
      final mpegTs = protocols.where(
        (entry) {
          final normalized = entry.toLowerCase();
          return normalized.contains('video/mp2t') ||
              normalized.contains('video/vnd.dlna.mpeg-tts') ||
              normalized.contains('video/mpeg');
        },
      ).toList();
      stdout.writeln(
        '  MPEG-TS: ${mpegTs.isEmpty ? '未声明' : mpegTs.join(', ')}',
      );
    } catch (error) {
      stdout.writeln('  ConnectionManager query: $error');
    }
  }
}
