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
  Timer? _statsTimer;
  final Stopwatch _statsClock = Stopwatch()..start();
  StageTextureStats? _lastStats;
  int? _lastStatsMicros;
  double? _publishedFps;
  double? _acquiredFps;

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
    if (!mounted) return;
    setState(() => _textureId = textureId);
    await _sampleStats();
    _statsTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => unawaited(_sampleStats()),
    );
  }

  Future<void> _sampleStats() async {
    final stats = await widget.textureController.readStats();
    if (!mounted || stats == null) return;
    final nowMicros = _statsClock.elapsedMicroseconds;
    final previous = _lastStats;
    final previousMicros = _lastStatsMicros;
    _lastStats = stats;
    _lastStatsMicros = nowMicros;
    if (previous == null || previousMicros == null) return;
    final elapsedSeconds = (nowMicros - previousMicros) / 1000000.0;
    if (elapsedSeconds <= 0) return;
    setState(() {
      _publishedFps =
          (stats.publishedFrames - previous.publishedFrames) / elapsedSeconds;
      _acquiredFps =
          (stats.acquiredFrames - previous.acquiredFrames) / elapsedSeconds;
    });
  }

  @override
  void dispose() {
    _statsTimer?.cancel();
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
          : Stack(
              fit: StackFit.expand,
              children: [
                Texture(
                  textureId: textureId,
                  filterQuality: FilterQuality.high,
                ),
                Positioned(
                  left: 16,
                  top: 16,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: const Color(0xd9111216),
                        border: Border.all(color: const Color(0x667c8391)),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 7,
                        ),
                        child: Text(
                          'STAGE ${_formatFps(_publishedFps)} FPS  |  '
                          'PREVIEW ${_formatFps(_acquiredFps)} FPS',
                          style: const TextStyle(
                            color: Color(0xffebedf0),
                            fontFamily: 'Consolas',
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  String _formatFps(double? value) {
    if (value == null || !value.isFinite) return '--.-';
    return value.clamp(0, 999).toStringAsFixed(1).padLeft(4);
  }
}
