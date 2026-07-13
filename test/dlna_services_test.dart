import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kirakara_app/services/cast_service.dart';
import 'package:kirakara_app/services/dlna/dlna_control_point.dart';
import 'package:kirakara_app/services/dlna/dlna_device.dart';
import 'package:kirakara_app/services/dlna/dlna_device_description_parser.dart';
import 'package:kirakara_app/services/dlna/dlna_discovery_service.dart';
import 'package:kirakara_app/services/dlna/dlna_http_client.dart';
import 'package:kirakara_app/services/display_manager.dart';
import 'package:kirakara_app/services/kirakara_show_service.dart';
import 'package:kirakara_app/services/native_window_service.dart';
import 'package:kirakara_app/services/playback_service.dart';
import 'package:kirakara_app/services/queue_service.dart';

void main() {
  group('SSDP discovery protocol', () {
    test('builds a standards-shaped M-SEARCH request', () {
      final request = DlnaDiscoveryService.buildSearchRequest(
        'urn:schemas-upnp-org:device:MediaRenderer:1',
      );

      expect(request, startsWith('M-SEARCH * HTTP/1.1\r\n'));
      expect(request, contains('HOST: 239.255.255.250:1900\r\n'));
      expect(request, contains('MAN: "ssdp:discover"\r\n'));
      expect(request, contains('MX: 2\r\n'));
      expect(request, endsWith('\r\n\r\n'));
    });

    test('parses response headers case-insensitively', () {
      final headers = DlnaDiscoveryService.parseResponseHeaders(
        'HTTP/1.1 200 OK\r\n'
        'LOCATION: http://192.168.1.20:1400/device.xml\r\n'
        'UsN: uuid:renderer::upnp:rootdevice\r\n\r\n',
      );

      expect(headers['location'], 'http://192.168.1.20:1400/device.xml');
      expect(headers['usn'], 'uuid:renderer::upnp:rootdevice');
    });
  });

  group('device description', () {
    test('finds an embedded renderer and resolves service URLs', () {
      const source = '''
        <?xml version="1.0"?>
        <root xmlns="urn:schemas-upnp-org:device-1-0">
          <URLBase>http://192.168.1.20:1400/base/</URLBase>
          <device>
            <deviceType>urn:schemas-upnp-org:device:Basic:1</deviceType>
            <friendlyName>Container</friendlyName>
            <deviceList>
              <device>
                <deviceType>urn:schemas-upnp-org:device:MediaRenderer:1</deviceType>
                <friendlyName>客厅电视</friendlyName>
                <manufacturer>Example</manufacturer>
                <modelName>Renderer X</modelName>
                <UDN>uuid:renderer-1</UDN>
                <serviceList>
                  <service>
                    <serviceType>urn:schemas-upnp-org:service:AVTransport:1</serviceType>
                    <serviceId>urn:upnp-org:serviceId:AVTransport</serviceId>
                    <controlURL>/upnp/control/avtransport</controlURL>
                    <eventSubURL>/upnp/event/avtransport</eventSubURL>
                    <SCPDURL>/avtransport.xml</SCPDURL>
                  </service>
                  <service>
                    <serviceType>urn:schemas-upnp-org:service:ConnectionManager:1</serviceType>
                    <serviceId>urn:upnp-org:serviceId:ConnectionManager</serviceId>
                    <controlURL>connection/control</controlURL>
                    <eventSubURL>connection/event</eventSubURL>
                    <SCPDURL>connection.xml</SCPDURL>
                  </service>
                </serviceList>
              </device>
            </deviceList>
          </device>
        </root>
      ''';

      final device = const DlnaDeviceDescriptionParser().parse(
        source,
        location: Uri.parse('http://192.168.1.20:1400/device.xml'),
        localAddress: '192.168.1.10',
      );

      expect(device.id, 'uuid:renderer-1');
      expect(device.friendlyName, '客厅电视');
      expect(device.detailLabel, 'Example · Renderer X');
      expect(
        device.avTransport.controlUrl.toString(),
        'http://192.168.1.20:1400/upnp/control/avtransport',
      );
      expect(
        device.connectionManager?.controlUrl.toString(),
        'http://192.168.1.20:1400/base/connection/control',
      );
    });

    test('rejects a device without MediaRenderer', () {
      expect(
        () => const DlnaDeviceDescriptionParser().parse(
          '<root><device><deviceType>urn:test:device:Other:1</deviceType>'
          '</device></root>',
          location: Uri.parse('http://192.168.1.20/device.xml'),
          localAddress: '192.168.1.10',
        ),
        throwsFormatException,
      );
    });
  });

  group('SOAP control', () {
    test('escapes transport arguments in the envelope', () {
      final envelope = DlnaControlPoint.buildSoapEnvelope(
        serviceType: 'urn:schemas-upnp-org:service:AVTransport:1',
        action: 'SetAVTransportURI',
        arguments: const {
          'InstanceID': '0',
          'CurrentURI': 'http://192.168.1.10/stage.ts?a=1&b=2',
          'CurrentURIMetaData': '<item>歌名</item>',
        },
      );

      expect(envelope, contains('<u:SetAVTransportURI'));
      expect(envelope, contains('a=1&amp;b=2'));
      expect(envelope, contains('&lt;item&gt;歌名&lt;/item&gt;'));
    });

    test('extracts UPnP error details', () {
      const fault = '''
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">
          <s:Body><s:Fault><detail><UPnPError>
            <errorCode>714</errorCode>
            <errorDescription>Illegal MIME-type</errorDescription>
          </UPnPError></detail></s:Fault></s:Body>
        </s:Envelope>
      ''';
      expect(
        DlnaControlPoint.parseSoapFault(fault),
        '714 · Illegal MIME-type',
      );
    });

    test('chooses a declared MPEG-TS protocol without copying a profile', () {
      expect(
        DlnaControlPoint.chooseMpegTsProtocolInfo(const [
          'http-get:*:video/vnd.dlna.mpeg-tts:DLNA.ORG_PN=AVC_TS_MP_HD_AAC_T',
          'http-get:*:video/mpeg:*',
        ]),
        'http-get:*:video/mpeg:*',
      );
      expect(
        DlnaControlPoint.chooseMpegTsProtocolInfo(const []),
        'http-get:*:video/MP2T:*',
      );
    });

    test('only accepts physical LAN HTTP URLs', () {
      expect(
        () => DlnaHttpClient.validateLanUri(
          Uri.parse('http://8.8.8.8/device.xml'),
        ),
        throwsFormatException,
      );
      expect(
        () => DlnaHttpClient.validateLanUri(
          Uri.parse('http://192.168.1.20/device.xml'),
        ),
        returnsNormally,
      );
    });
  });

  group('CastService state machine', () {
    test('connects and disconnects without disabling wireless mode', () async {
      final device = _device();
      final discovery = _FakeDiscoveryService([device]);
      final control = _FakeControlPoint();
      final show = _FakeShowService();
      final service = CastService(
        discoveryService: discovery,
        controlPoint: control,
      );
      addTearDown(service.dispose);

      await service.enableCastMode();
      expect(service.isEnabled, isTrue);
      expect(service.devices, [device]);

      final gate = Completer<void>();
      control.connectGate = gate;
      final connecting = service.connectToDevice(device, show);
      await Future<void>.delayed(Duration.zero);

      expect(service.state, CastState.searching);
      expect(service.activeDevice, device);
      expect(show.startCalls, 1);
      expect(
          control.lastStreamUri,
          Uri.parse(
            'http://192.168.31.99:14000/cast/stage.ts',
          ));

      gate.complete();
      await connecting;
      expect(service.isCasting, isTrue);
      expect(service.mpegTsUrl, control.lastStreamUri.toString());

      await service.connectToDevice(device, show);
      expect(service.state, CastState.idle);
      expect(service.isEnabled, isTrue);
      expect(service.activeDevice, isNull);
      expect(control.stopCalls, 1);
      expect(show.stopCalls, greaterThanOrEqualTo(2));

      await service.disableCastMode(showService: show);
      expect(service.isEnabled, isFalse);
      expect(service.devices, isEmpty);
    });

    test('rolls back the native stream when the receiver rejects control',
        () async {
      final device = _device();
      final control = _FakeControlPoint()
        ..connectError = const DlnaSoapException(
          action: 'SetAVTransportURI',
          statusCode: 500,
          message: '714 · Illegal MIME-type',
        );
      final show = _FakeShowService();
      final service = CastService(
        discoveryService: _FakeDiscoveryService([device]),
        controlPoint: control,
      );
      addTearDown(service.dispose);

      await service.enableCastMode();
      await expectLater(
        service.connectToDevice(device, show),
        throwsA(isA<DlnaSoapException>()),
      );

      expect(service.state, CastState.idle);
      expect(service.isEnabled, isTrue);
      expect(service.activeDevice, isNull);
      expect(service.mpegTsUrl, isNull);
      expect(service.lastError, contains('Illegal MIME-type'));
      expect(show.startCalls, 1);
      expect(show.stopCalls, greaterThanOrEqualTo(2));
    });

    test('cleans up locally when the receiver stops the transport', () async {
      final device = _device();
      final control = _FakeControlPoint()
        ..transportStates.addAll(const [
          DlnaTransportState.playing,
          DlnaTransportState.stopped,
          DlnaTransportState.stopped,
        ]);
      final show = _FakeShowService();
      final service = CastService(
        discoveryService: _FakeDiscoveryService([device]),
        controlPoint: control,
        receiverMonitorInterval: const Duration(milliseconds: 5),
      );
      addTearDown(service.dispose);

      await service.enableCastMode();
      await service.connectToDevice(device, show);
      expect(service.isCasting, isTrue);

      for (var i = 0; i < 40 && service.isCasting; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }

      expect(service.state, CastState.idle);
      expect(service.isEnabled, isTrue);
      expect(service.activeDevice, isNull);
      expect(service.mpegTsUrl, isNull);
      expect(service.lastError, contains('已断开'));
      expect(show.stopCalls, greaterThanOrEqualTo(2));
    });

    test('keeps casting when transport monitoring is unsupported', () async {
      final device = _device();
      final control = _FakeControlPoint()
        ..transportError = const DlnaSoapException(
          action: 'GetTransportInfo',
          statusCode: 500,
          message: '401 · Invalid Action',
        );
      final show = _FakeShowService();
      final service = CastService(
        discoveryService: _FakeDiscoveryService([device]),
        controlPoint: control,
        receiverMonitorInterval: const Duration(milliseconds: 5),
      );
      addTearDown(service.dispose);

      await service.enableCastMode();
      await service.connectToDevice(device, show);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(service.isCasting, isTrue);
      expect(service.activeDevice, device);
      expect(service.lastError, isNull);
    });
  });

  test('display selection survives refresh while the display remains',
      () async {
    final native = _FakeNativeWindowService([
      _display('primary', primary: true, left: 0),
      _display('second', left: 1920),
      _display('third', left: 3840),
    ]);
    final manager = DisplayManager(nativeWindowService: native);
    await manager.detectDisplays();
    manager.selectStageDisplay('third');

    expect(manager.stageDisplay?.id, 'third');
    await manager.detectDisplays();
    expect(manager.stageDisplay?.id, 'third');

    native.displays = [
      _display('primary', primary: true, left: 0),
      _display('second', left: 1920),
    ];
    await manager.detectDisplays();
    expect(manager.stageDisplay?.id, 'second');
  });
}

Map<String, Object?> _display(
  String id, {
  bool primary = false,
  required int left,
}) {
  return {
    'id': id,
    'name': id,
    'isPrimary': primary,
    'left': left,
    'top': 0,
    'width': 1920,
    'height': 1080,
  };
}

class _FakeNativeWindowService extends NativeWindowService {
  _FakeNativeWindowService(this.displays);

  List<Map<String, Object?>> displays;

  @override
  Future<List<Map<String, Object?>>> getDisplays() async => displays;
}

DlnaDevice _device() {
  return DlnaDevice(
    id: 'uuid:renderer',
    friendlyName: '测试电视',
    manufacturer: 'Example',
    modelName: 'Renderer',
    location: Uri.parse('http://192.168.31.214/device.xml'),
    localAddress: '192.168.31.99',
    avTransport: DlnaServiceEndpoint(
      serviceType: 'urn:schemas-upnp-org:service:AVTransport:1',
      controlUrl: Uri.parse('http://192.168.31.214/avtransport'),
    ),
  );
}

class _FakeDiscoveryService extends DlnaDiscoveryService {
  _FakeDiscoveryService(this.result);

  final List<DlnaDevice> result;

  @override
  Future<List<DlnaDevice>> discover({
    Duration responseWindow = const Duration(milliseconds: 2600),
  }) async {
    return result;
  }
}

class _FakeControlPoint extends DlnaControlPoint {
  Completer<void>? connectGate;
  Object? connectError;
  Uri? lastStreamUri;
  int stopCalls = 0;
  final List<DlnaTransportState> transportStates = [];
  Object? transportError;

  @override
  Future<void> setTransportUriAndPlay(
    DlnaDevice device,
    Uri streamUri, {
    String title = 'Kira Karaoke',
  }) async {
    lastStreamUri = streamUri;
    final error = connectError;
    if (error != null) throw error;
    await connectGate?.future;
  }

  @override
  Future<void> stop(DlnaDevice device) async {
    stopCalls++;
  }

  @override
  Future<DlnaTransportState> getTransportState(DlnaDevice device) async {
    final error = transportError;
    if (error != null) throw error;
    if (transportStates.isEmpty) return DlnaTransportState.playing;
    return transportStates.removeAt(0);
  }
}

class _FakeShowService extends KirakaraShowService {
  _FakeShowService()
      : super(
          playbackService: PlaybackService(queueService: QueueService()),
        );

  int startCalls = 0;
  int stopCalls = 0;

  @override
  bool startCastStream(int port) {
    startCalls++;
    return true;
  }

  @override
  int get castStreamPort => 14000;

  @override
  void stopCastStream() {
    stopCalls++;
  }
}
