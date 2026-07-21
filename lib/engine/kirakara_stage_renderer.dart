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
        _stageTextureController = StageTextureController();

  final KirakaraShowService _showService;
  final StageTextureController _stageTextureController;

  @override
  Widget buildStage({
    required PlaybackState playbackState,
    required MediaFrame mediaFrame,
    required RenderPreset preset,
  }) {
    if (Platform.isWindows) {
      return _KirakaraGpuStageWidget(
        showService: _showService,
        textureController: _stageTextureController,
      );
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
  int? _textureId;

  @override
  void initState() {
    super.initState();
    unawaited(_attachTexture());
  }

  Future<void> _attachTexture() async {
    final textureId = await widget.textureController.attach(
      widget.showService.nativeHandleAddress,
    );
    if (!mounted) {
      await widget.textureController.setActive(false);
      return;
    }
    if (textureId == null) return;
    await widget.textureController.setActive(true);
    if (mounted) setState(() => _textureId = textureId);
  }

  @override
  void dispose() {
    unawaited(widget.textureController.setActive(false));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textureId = _textureId;
    return ColoredBox(
      color: Colors.black,
      child: textureId == null
          ? const SizedBox.expand()
          : Texture(
              textureId: textureId,
              filterQuality: FilterQuality.high,
            ),
    );
  }
}
