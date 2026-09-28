import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../domain/playback_state.dart';
import '../services/kirakara_show_service.dart';
import '../services/stage_texture_service.dart';
import 'stage_renderer.dart';

class KirakaraStageRenderer implements StageRenderer {
  KirakaraStageRenderer({
    required KirakaraShowService showService,
  })  : _showService = showService,
        _stageTextureController = StageTextureController() {
    _windowsStage = _KirakaraGpuStageWidget(
      showService: _showService,
      textureController: _stageTextureController,
    );
  }

  final KirakaraShowService _showService;
  final StageTextureController _stageTextureController;
  late final Widget _windowsStage;

  @override
  Widget buildStage({
    required PlaybackState playbackState,
    required MediaFrame mediaFrame,
    required RenderPreset preset,
  }) {
    if (Platform.isWindows) {
      // Keep the external texture element stable when unrelated controller
      // state changes. Native Show drives frame availability directly;
      // rebuilding this subtree cannot advance it.
      return _windowsStage;
    }
    return ColoredBox(color: mediaFrame.backgroundColor);
  }
}

class _KirakaraGpuStageWidget extends StatefulWidget {
  const _KirakaraGpuStageWidget({
    required this.showService,
    required this.textureController,
  });

  final KirakaraShowService showService;
  final StageTextureController textureController;

  @override
  State<_KirakaraGpuStageWidget> createState() =>
      _KirakaraGpuStageWidgetState();
}

class _KirakaraGpuStageWidgetState extends State<_KirakaraGpuStageWidget> {
  StagePresentationAttachment? _attachment;

  @override
  void initState() {
    super.initState();
    unawaited(_attachTexture());
  }

  Future<void> _attachTexture() async {
    final attachment = await widget.textureController.attach(
      widget.showService.nativeHandleAddress,
    );
    if (!mounted) {
      await widget.textureController.setActive(false);
      return;
    }
    if (attachment == null) return;
    setState(() => _attachment = attachment);
    if (attachment.isComposed) {
      // Let the transparent slot publish its physical bounds before Show can
      // deliver the first frame. The Engine keeps the lower Visual detached
      // until both geometry and a resource are available.
      await WidgetsBinding.instance.endOfFrame;
    }
    if (!mounted) return;
    await widget.textureController.setActive(true);
  }

  @override
  void dispose() {
    unawaited(widget.textureController.setActive(false));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final attachment = _attachment;
    if (attachment == null) {
      return const ColoredBox(color: Colors.black);
    }
    if (attachment.isComposed) {
      return _ComposedStageHole(controller: widget.textureController);
    }
    return ColoredBox(
      color: Colors.black,
      child: Texture(
        textureId: attachment.textureId!,
        filterQuality: FilterQuality.high,
      ),
    );
  }
}

class _ComposedStageHole extends StatefulWidget {
  const _ComposedStageHole({required this.controller});

  final StageTextureController controller;

  @override
  State<_ComposedStageHole> createState() => _ComposedStageHoleState();
}

class _ComposedStageHoleState extends State<_ComposedStageHole>
    with WidgetsBindingObserver {
  final _slotKey = GlobalKey();
  bool _reportScheduled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scheduleGeometryReport();
  }

  @override
  void didUpdateWidget(_ComposedStageHole oldWidget) {
    super.didUpdateWidget(oldWidget);
    _scheduleGeometryReport();
  }

  @override
  void didChangeMetrics() {
    _scheduleGeometryReport();
  }

  void _scheduleGeometryReport() {
    if (_reportScheduled) return;
    _reportScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _reportScheduled = false;
      if (!mounted) return;
      final renderObject =
          _slotKey.currentContext?.findRenderObject() as RenderBox?;
      if (renderObject == null || !renderObject.hasSize) return;
      final logicalTopLeft = renderObject.localToGlobal(Offset.zero);
      final logicalBounds = logicalTopLeft & renderObject.size;
      final scale = View.of(context).devicePixelRatio;
      unawaited(widget.controller.setComposedGeometry(
        physicalBounds: Rect.fromLTWH(
          logicalBounds.left * scale,
          logicalBounds.top * scale,
          logicalBounds.width * scale,
          logicalBounds.height * scale,
        ),
      ));
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _scheduleGeometryReport();
    return CustomPaint(
      key: _slotKey,
      painter: const _ClearStageHolePainter(),
      child: const SizedBox.expand(),
    );
  }
}

class _ClearStageHolePainter extends CustomPainter {
  const _ClearStageHolePainter();

  @override
  void paint(Canvas canvas, Size size) {
    // Do not wrap this in saveLayer: the clear operation intentionally removes
    // the already-painted Flutter background from the upper premultiplied-alpha
    // surface. Later Stack children (buttons, dialogs, masks) paint above it.
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..isAntiAlias = false
        ..blendMode = BlendMode.clear,
    );
  }

  @override
  bool shouldRepaint(covariant _ClearStageHolePainter oldDelegate) => false;
}
