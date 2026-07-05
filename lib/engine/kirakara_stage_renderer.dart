import 'package:flutter/material.dart';

import '../domain/playback_state.dart';
import '../services/kirakara_show_service.dart';
import '../services/native_window_service.dart';
import 'stage_renderer.dart';

class KirakaraStageRenderer implements StageRenderer {
  KirakaraStageRenderer({
    required KirakaraShowService showService,
    NativeWindowService nativeWindowService = const NativeWindowService(),
  })  : _showService = showService,
        _nativeWindowService = nativeWindowService;

  final KirakaraShowService _showService;
  final NativeWindowService _nativeWindowService;

  @override
  Widget buildStage({
    required PlaybackState playbackState,
    required MediaFrame mediaFrame,
    required RenderPreset preset,
  }) {
    return _KirakaraNativeStageWidget(
      showService: _showService,
      nativeWindowService: _nativeWindowService,
      fallbackColor: mediaFrame.backgroundColor,
    );
  }
}

class _KirakaraNativeStageWidget extends StatefulWidget {
  const _KirakaraNativeStageWidget({
    required this.showService,
    required this.nativeWindowService,
    required this.fallbackColor,
  });

  final KirakaraShowService showService;
  final NativeWindowService nativeWindowService;
  final Color fallbackColor;

  @override
  State<_KirakaraNativeStageWidget> createState() =>
      _KirakaraNativeStageWidgetState();
}

class _NativePreviewRect {
  const _NativePreviewRect({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  final int x;
  final int y;
  final int width;
  final int height;

  @override
  bool operator ==(Object other) {
    return other is _NativePreviewRect &&
        other.x == x &&
        other.y == y &&
        other.width == width &&
        other.height == height;
  }

  @override
  int get hashCode => Object.hash(x, y, width, height);
}

class _KirakaraNativeStageWidgetState
    extends State<_KirakaraNativeStageWidget> {
  int? _parentHwnd;
  _NativePreviewRect? _lastRect;
  _NativePreviewRect? _lastQrRect;
  bool _syncScheduled = false;

  @override
  void initState() {
    super.initState();
    widget.showService.addListener(_handleShowServiceChanged);
    _loadWindowHandle();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scheduleSync();
  }

  @override
  void didUpdateWidget(covariant _KirakaraNativeStageWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.showService != widget.showService) {
      oldWidget.showService.removeListener(_handleShowServiceChanged);
      widget.showService.addListener(_handleShowServiceChanged);
    }
    _scheduleSync();
  }

  @override
  void dispose() {
    widget.showService.removeListener(_handleShowServiceChanged);
    widget.showService.hideControllerPreview();
    super.dispose();
  }

  void _handleShowServiceChanged() {
    _scheduleSync();
  }

  Future<void> _loadWindowHandle() async {
    final handle = await widget.nativeWindowService.getFlutterViewHandle();
    if (!mounted) return;
    setState(() => _parentHwnd = handle);
    _scheduleSync();
  }

  void _scheduleSync() {
    if (_syncScheduled) return;
    _syncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncScheduled = false;
      if (mounted) _syncNativePreviewRect();
    });
  }

  void _syncNativePreviewRect() {
    if (widget.showService.controllerPreviewSuppressed) {
      _lastRect = null;
      widget.showService.hideControllerPreview();
      return;
    }

    final parentHwnd = _parentHwnd;
    if (parentHwnd == null) return;

    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return;

    final designSize = renderObject.size;
    final topLeft = renderObject.localToGlobal(Offset.zero);
    final bottomRight = renderObject.localToGlobal(
      Offset(designSize.width, designSize.height),
    );
    final paintedWidth = bottomRight.dx - topLeft.dx;
    final paintedHeight = bottomRight.dy - topLeft.dy;

    // KiraDesignCanvas scales the whole 1920x1080 UI with FittedBox. Use the
    // transformed corners above so the native HWND follows Flutter's painted
    // size instead of the unscaled design size.
    var stageHeight = paintedHeight;
    var stageWidth = stageHeight * 16 / 9;
    if (stageWidth > paintedWidth) {
      stageWidth = paintedWidth;
      stageHeight = stageWidth * 9 / 16;
    }
    final stageLeft = topLeft.dx + (paintedWidth - stageWidth) / 2;
    final stageTop = topLeft.dy + (paintedHeight - stageHeight) / 2;
    final rect = _NativePreviewRect(
      x: stageLeft.round(),
      y: stageTop.round(),
      width: stageWidth.round().clamp(1, 16384),
      height: stageHeight.round().clamp(1, 16384),
    );
    if (rect != _lastRect) {
      _lastRect = rect;
      widget.showService.setControllerPreviewRect(
        parentHwnd: parentHwnd,
        x: rect.x,
        y: rect.y,
        width: rect.width,
        height: rect.height,
      );
    }

    final scaleX = stageWidth / designSize.width;
    final scaleY = stageHeight / designSize.height;
    const qrDesignSize = 145.0;
    const qrDesignRight = 22.0;
    const qrDesignTop = 90.0;
    final qrSize = (qrDesignSize * ((scaleX + scaleY) / 2)).round();
    final qrRect = _NativePreviewRect(
      x: ((designSize.width - qrDesignRight - qrDesignSize) * scaleX).round(),
      y: (qrDesignTop * scaleY).round(),
      width: qrSize.clamp(1, 4096),
      height: qrSize.clamp(1, 4096),
    );
    if (qrRect != _lastQrRect) {
      _lastQrRect = qrRect;
      widget.showService.setControllerQrRect(
        visible: true,
        x: qrRect.x,
        y: qrRect.y,
        size: qrRect.width,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    _scheduleSync();
    return SizedBox.expand(
      child: ColoredBox(
        color: _parentHwnd == null ? widget.fallbackColor : Colors.black,
      ),
    );
  }
}
