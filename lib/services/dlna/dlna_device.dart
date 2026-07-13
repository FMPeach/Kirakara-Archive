class DlnaServiceEndpoint {
  const DlnaServiceEndpoint({
    required this.serviceType,
    required this.controlUrl,
  });

  final String serviceType;
  final Uri controlUrl;
}

class DlnaDevice {
  const DlnaDevice({
    required this.id,
    required this.friendlyName,
    required this.location,
    required this.localAddress,
    required this.avTransport,
    this.manufacturer = '',
    this.modelName = '',
    this.iconUrl,
    this.connectionManager,
    this.renderingControl,
  });

  final String id;
  final String friendlyName;
  final String manufacturer;
  final String modelName;
  final Uri location;
  final String localAddress;
  final Uri? iconUrl;
  final DlnaServiceEndpoint avTransport;
  final DlnaServiceEndpoint? connectionManager;
  final DlnaServiceEndpoint? renderingControl;

  String get detailLabel {
    final parts = <String>[
      if (manufacturer.trim().isNotEmpty) manufacturer.trim(),
      if (modelName.trim().isNotEmpty) modelName.trim(),
    ];
    return parts.isEmpty ? 'DLNA 播放设备' : parts.join(' · ');
  }
}
