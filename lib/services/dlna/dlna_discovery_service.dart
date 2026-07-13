import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../lan_address_resolver.dart';
import 'dlna_device.dart';
import 'dlna_device_description_parser.dart';
import 'dlna_http_client.dart';

typedef DlnaDescriptionLoader = Future<String> Function(
  Uri location,
  String localAddress,
);

class DlnaDiscoveryException implements Exception {
  const DlnaDiscoveryException(this.message);

  final String message;

  @override
  String toString() => message;
}

class DlnaDiscoveryService {
  DlnaDiscoveryService({
    DlnaDeviceDescriptionParser parser = const DlnaDeviceDescriptionParser(),
    DlnaDescriptionLoader? descriptionLoader,
  })  : _parser = parser,
        _descriptionLoader = descriptionLoader ?? _loadDescription;

  static final InternetAddress _multicastAddress =
      InternetAddress('239.255.255.250');
  static const int _multicastPort = 1900;
  static const List<String> _searchTargets = [
    'urn:schemas-upnp-org:device:MediaRenderer:1',
    'ssdp:all',
  ];

  final DlnaDeviceDescriptionParser _parser;
  final DlnaDescriptionLoader _descriptionLoader;

  Future<List<DlnaDevice>> discover({
    Duration responseWindow = const Duration(milliseconds: 2600),
  }) async {
    final localAddress = await LanAddressResolver.detectIpv4();
    if (localAddress == null) {
      throw const DlnaDiscoveryException(
        '未找到可用的实体局域网 IPv4，请检查 Wi-Fi 或网线连接',
      );
    }

    final socket = await RawDatagramSocket.bind(
      InternetAddress(localAddress),
      0,
      reuseAddress: true,
    );
    socket.multicastHops = 4;
    final responses = <Uri, String?>{};
    final subscription = socket.listen((event) {
      if (event != RawSocketEvent.read) return;
      Datagram? datagram;
      while ((datagram = socket.receive()) != null) {
        final packet = ascii.decode(datagram!.data, allowInvalid: true);
        final headers = parseResponseHeaders(packet);
        final locationText = headers['location'];
        if (locationText == null) continue;
        final location = Uri.tryParse(locationText.trim());
        if (location == null) continue;
        try {
          DlnaHttpClient.validateLanUri(location);
        } catch (_) {
          continue;
        }
        responses.putIfAbsent(location, () => headers['usn']);
      }
    });

    try {
      for (var pass = 0; pass < 2; pass++) {
        for (final target in _searchTargets) {
          socket.send(
            ascii.encode(buildSearchRequest(target)),
            _multicastAddress,
            _multicastPort,
          );
          await Future<void>.delayed(const Duration(milliseconds: 80));
        }
      }
      await Future<void>.delayed(responseWindow);
    } finally {
      await subscription.cancel();
      socket.close();
    }

    final devices = <String, DlnaDevice>{};
    await Future.wait(
      responses.entries.map((entry) async {
        try {
          final source = await _descriptionLoader(entry.key, localAddress);
          final device = _parser.parse(
            source,
            location: entry.key,
            localAddress: localAddress,
            usn: entry.value,
          );
          devices[device.id] = device;
        } catch (_) {
          // SSDP commonly returns routers and media servers for ssdp:all.
        }
      }),
    );
    final result = devices.values.toList()
      ..sort(
        (left, right) => left.friendlyName.toLowerCase().compareTo(
              right.friendlyName.toLowerCase(),
            ),
      );
    return result;
  }

  static String buildSearchRequest(String searchTarget) {
    return 'M-SEARCH * HTTP/1.1\r\n'
        'HOST: 239.255.255.250:1900\r\n'
        'MAN: "ssdp:discover"\r\n'
        'MX: 2\r\n'
        'ST: $searchTarget\r\n'
        'USER-AGENT: Windows/10 UPnP/1.1 Kirakara/0.1\r\n'
        '\r\n';
  }

  static Map<String, String> parseResponseHeaders(String packet) {
    final lines = const LineSplitter().convert(packet);
    if (lines.isEmpty || !lines.first.toUpperCase().contains('200 OK')) {
      return const {};
    }
    final headers = <String, String>{};
    for (final line in lines.skip(1)) {
      final separator = line.indexOf(':');
      if (separator <= 0) continue;
      final name = line.substring(0, separator).trim().toLowerCase();
      final value = line.substring(separator + 1).trim();
      if (name.isNotEmpty && value.isNotEmpty) headers[name] = value;
    }
    return headers;
  }

  static Future<String> _loadDescription(
    Uri location,
    String localAddress,
  ) {
    return DlnaHttpClient.getText(
      location,
      localAddress: localAddress,
    );
  }
}
