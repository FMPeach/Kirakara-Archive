import 'package:kirakara_app/services/dlna/dlna_control_point.dart';
import 'package:kirakara_app/services/dlna/dlna_discovery_service.dart';

Future<void> main() async {
  final discovery = DlnaDiscoveryService();
  final controlPoint = const DlnaControlPoint();

  print('正在扫描实体局域网内的 DLNA MediaRenderer...');
  final devices = await discovery.discover(
    responseWindow: const Duration(seconds: 4),
  );
  if (devices.isEmpty) {
    print('未发现设备。');
    return;
  }

  for (final device in devices) {
    print('${device.friendlyName} (${device.detailLabel})');
    print('  LOCATION: ${device.location}');
    print('  AVTransport: ${device.avTransport.controlUrl}');
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
      print('  MPEG-TS: ${mpegTs.isEmpty ? '未声明' : mpegTs.join(', ')}');
    } catch (error) {
      print('  ConnectionManager: $error');
    }
  }
}
