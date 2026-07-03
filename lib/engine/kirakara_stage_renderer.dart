import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../domain/playback_state.dart';
import '../services/kirakara_show_service.dart';
import 'stage_renderer.dart';

class KirakaraStageRenderer implements StageRenderer {
  KirakaraStageRenderer({required KirakaraShowService showService})
    : _showService = showService;

  final KirakaraShowService _showService;
  ui.Image? _cachedImage;
  Uint8List? _lastFrameData;
  bool _decoding = false;

  @override
  Widget buildStage({
    required PlaybackState playbackState,
    required MediaFrame mediaFrame,
    required RenderPreset preset,
  }) {
    return _KirakaraStageWidget(
      showService: _showService,
      fallbackColor: mediaFrame.backgroundColor,
    );
  }
}

class _KirakaraStageWidget extends StatefulWidget {
  const _KirakaraStageWidget({
    required this.showService,
    required this.fallbackColor,
  });

  final KirakaraShowService showService;
  final Color fallbackColor;

  @override
  State<_KirakaraStageWidget> createState() => _KirakaraStageWidgetState();
}

class _KirakaraStageWidgetState extends State<_KirakaraStageWidget> {
  ui.Image? _image;
  Uint8List? _lastFrame;
  bool _decoding = false;

  @override
  void initState() {
    super.initState();
    widget.showService.addListener(_onFrame);
  }

  @override
  void dispose() {
    widget.showService.removeListener(_onFrame);
    _image?.dispose();
    super.dispose();
  }

  void _onFrame() {
    final frame = widget.showService.latestFrame;
    if (frame == null || _decoding) return;
    if (identical(frame, _lastFrame)) return;
    _lastFrame = frame;

    _decoding = true;
    final width = widget.showService.engineWidth.clamp(1, 8192);
    final height = widget.showService.engineHeight.clamp(1, 8192);

    // Engine outputs BGRA → decode as bgra8888 directly, no channel swap needed
    ui.decodeImageFromPixels(
      frame,
      width,
      height,
      ui.PixelFormat.bgra8888,
      (image) {
        if (!mounted) {
          image.dispose();
          return;
        }
        final old = _image;
        _image = image;
        old?.dispose();
        _decoding = false;
        setState(() {});
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final img = _image;
    if (img != null) {
      return SizedBox.expand(
        child: RawImage(
          image: img,
          fit: BoxFit.fill,
          filterQuality: FilterQuality.low,
        ),
      );
    }

    // Fallback: show a colored stage while waiting for engine frames
    return ColoredBox(
      color: widget.fallbackColor,
      child: const Center(
        child: Text(
          '等待引擎画面…',
          style: TextStyle(
            color: Color(0x66FFFFFF),
            fontSize: 24,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
