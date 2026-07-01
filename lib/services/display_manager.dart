import 'package:flutter/foundation.dart';

enum DisplayMode {
  singleScreen,
  dualScreen,
  previewWindow,
}

class DisplayInfo {
  const DisplayInfo({
    required this.id,
    required this.name,
    required this.isPrimary,
  });

  final String id;
  final String name;
  final bool isPrimary;
}

class DisplayManager extends ChangeNotifier {
  DisplayManager()
      : _displays = const [
          DisplayInfo(id: 'primary', name: '主控屏', isPrimary: true),
        ];

  List<DisplayInfo> _displays;
  DisplayMode _mode = DisplayMode.singleScreen;
  bool _stagePreviewVisible = true;

  List<DisplayInfo> get displays => List.unmodifiable(_displays);
  DisplayMode get mode => _mode;
  bool get hasPhysicalStageDisplay => _displays.length > 1;
  bool get stagePreviewVisible => _stagePreviewVisible;

  Future<void> detectDisplays() async {
    // Replace with native display enumeration on Windows/Android later.
    _displays = const [
      DisplayInfo(id: 'primary', name: '主控屏', isPrimary: true),
    ];
    _mode = hasPhysicalStageDisplay ? DisplayMode.dualScreen : _mode;
    notifyListeners();
  }

  Future<void> openStageWindow({bool preview = true}) async {
    _stagePreviewVisible = preview;
    _mode = preview ? DisplayMode.previewWindow : DisplayMode.dualScreen;
    notifyListeners();
  }

  Future<void> closeStageWindow() async {
    _stagePreviewVisible = false;
    _mode = DisplayMode.singleScreen;
    notifyListeners();
  }

  Future<void> savePreference(DisplayMode mode) async {
    _mode = mode;
    notifyListeners();
  }
}
