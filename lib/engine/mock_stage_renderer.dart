import 'package:flutter/material.dart';

import '../domain/playback_state.dart';
import 'stage_renderer.dart';

class MockStageRenderer implements StageRenderer {
  const MockStageRenderer();

  @override
  Widget buildStage({
    required PlaybackState playbackState,
    required MediaFrame mediaFrame,
    required RenderPreset preset,
  }) {
    return _MockStageCanvas(
      playbackState: playbackState,
      mediaFrame: mediaFrame,
      preset: preset,
    );
  }
}

class _MockStageCanvas extends StatelessWidget {
  const _MockStageCanvas({
    required this.playbackState,
    required this.mediaFrame,
    required this.preset,
  });

  final PlaybackState playbackState;
  final MediaFrame mediaFrame;
  final RenderPreset preset;

  @override
  Widget build(BuildContext context) {
    const mockLoop = Duration(seconds: 12);
    final progress = playbackState.position.inMilliseconds <= 0
        ? 0.0
        : (playbackState.position.inMilliseconds % mockLoop.inMilliseconds) /
            mockLoop.inMilliseconds;

    return AspectRatio(
      aspectRatio: 16 / 9,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: Colors.black,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xff000000),
              Color(0xff030304),
              Colors.black,
            ],
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            CustomPaint(painter: _StageLightPainter(progress: progress)),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0x22000000),
                    Color(0x11000000),
                    Color(0xdd000000),
                  ],
                ),
              ),
            ),
            if (preset.showGuidePills)
              Positioned(
                left: 28,
                top: 24,
                child: _StagePill(
                  dotColor: playbackState.isPlaying
                      ? const Color(0xff22c59b)
                      : const Color(0xfff2b84b),
                  text: playbackState.isPlaying ? '正在播放' : '等待播放',
                ),
              ),
            if (preset.showGuidePills)
              Positioned(
                right: 28,
                top: 24,
                child: _StagePill(
                  text: _format(playbackState.position),
                ),
              ),
            Positioned(
              left: 90,
              right: 90,
              bottom: 54,
              child: Column(
                children: [
                  const Text(
                    'いたみに',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 21,
                      fontWeight: FontWeight.w700,
                      shadows: _stroke2,
                    ),
                  ),
                  const SizedBox(height: 5),
                  RichText(
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    text: const TextSpan(
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 70,
                        height: 1.05,
                        fontWeight: FontWeight.w700,
                        shadows: _stroke4,
                      ),
                      children: [
                        TextSpan(
                          text: '痛みに慣れてる',
                          style: TextStyle(
                            color: Color(0xfffff06a),
                            shadows: _hotStroke,
                          ),
                        ),
                        TextSpan(text: ' フリをしていた'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    '無数にできてた傷',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Color(0xeefafafa),
                      fontSize: 48,
                      fontWeight: FontWeight.w700,
                      shadows: _stroke4,
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: LinearProgressIndicator(
                minHeight: 5,
                value: progress,
                color: const Color(0xfff2b84b),
                backgroundColor: const Color(0x66000000),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _format(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

class _StagePill extends StatelessWidget {
  const _StagePill({
    required this.text,
    this.dotColor,
  });

  final String text;
  final Color? dotColor;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xbb111216),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0x2fffffff)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (dotColor != null) ...[
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: dotColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
            ],
            Text(
              text,
              style: const TextStyle(
                color: Color(0xfff4eee2),
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StageLightPainter extends CustomPainter {
  const _StageLightPainter({
    required this.progress,
  });

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    paint.shader = RadialGradient(
      colors: [
        const Color(0xffdd3e38).withValues(alpha: 0.16),
        const Color(0xffdd3e38).withValues(alpha: 0.02),
        Colors.transparent,
      ],
    ).createShader(
      Rect.fromCircle(
        center:
            Offset(size.width * (0.18 + progress * 0.6), size.height * 0.28),
        radius: size.shortestSide * 0.62,
      ),
    );
    canvas.drawRect(Offset.zero & size, paint);

    final beamPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.06)
      ..strokeWidth = size.width * 0.07
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(size.width * 0.12, 0),
      Offset(size.width * (0.5 + progress * 0.2), size.height),
      beamPaint,
    );
    canvas.drawLine(
      Offset(size.width * 0.9, 0),
      Offset(size.width * (0.45 - progress * 0.12), size.height),
      beamPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _StageLightPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

const _stroke2 = [
  Shadow(offset: Offset(2, 0), color: Color(0xff101114)),
  Shadow(offset: Offset(-2, 0), color: Color(0xff101114)),
  Shadow(offset: Offset(0, 2), color: Color(0xff101114)),
  Shadow(offset: Offset(0, -2), color: Color(0xff101114)),
];

const _stroke4 = [
  Shadow(offset: Offset(4, 0), color: Color(0xff101114)),
  Shadow(offset: Offset(-4, 0), color: Color(0xff101114)),
  Shadow(offset: Offset(0, 4), color: Color(0xff101114)),
  Shadow(offset: Offset(0, -4), color: Color(0xff101114)),
  Shadow(offset: Offset(0, 10), blurRadius: 22, color: Color(0x85000000)),
];

const _hotStroke = [
  Shadow(offset: Offset(4, 0), color: Color(0xffa91f1a)),
  Shadow(offset: Offset(-4, 0), color: Color(0xffa91f1a)),
  Shadow(offset: Offset(0, 4), color: Color(0xffa91f1a)),
  Shadow(offset: Offset(0, -4), color: Color(0xffa91f1a)),
  Shadow(offset: Offset(0, 10), blurRadius: 22, color: Color(0x85000000)),
];
