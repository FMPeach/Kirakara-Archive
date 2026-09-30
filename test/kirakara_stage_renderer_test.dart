import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kirakara_app/domain/playback_state.dart';
import 'package:kirakara_app/domain/queue_item.dart';
import 'package:kirakara_app/domain/song.dart';
import 'package:kirakara_app/engine/kirakara_stage_renderer.dart';
import 'package:kirakara_app/engine/stage_renderer.dart';
import 'package:kirakara_app/services/kirakara_show_service.dart';
import 'package:kirakara_app/services/playback_service.dart';
import 'package:kirakara_app/services/queue_service.dart';

void main() {
  test('Windows Stage stays black until a song is selected', () async {
    final queueService = QueueService();
    final playbackService = PlaybackService(queueService: queueService);
    final showService = KirakaraShowService(playbackService: playbackService);
    final renderer = KirakaraStageRenderer(showService: showService);
    addTearDown(() async {
      await showService.dispose();
      playbackService.dispose();
      queueService.dispose();
    });

    final idle = renderer.buildStage(
      playbackState: PlaybackState.initial(),
      mediaFrame: const MediaFrame(backgroundColor: Color(0xffffffff)),
      preset: const RenderPreset(),
    );

    expect(idle, isA<Stack>());
    final idleStack = idle as Stack;
    expect(idleStack.children, hasLength(2));
    expect(
      idleStack.children.last,
      isA<ColoredBox>().having(
        (box) => box.color,
        'color',
        const Color(0xff000000),
      ),
    );

    final selected = renderer.buildStage(
      playbackState: PlaybackState.initial(
        currentItem: QueueItem(
          id: 'queue-item',
          song: const Song(
            id: 'song',
            title: 'Song',
            category: 'test',
            assets: [],
          ),
          addedAt: DateTime.utc(2026),
        ),
      ),
      mediaFrame: const MediaFrame(backgroundColor: Color(0xffffffff)),
      preset: const RenderPreset(),
    );

    expect((selected as Stack).children, hasLength(1));
  }, skip: !Platform.isWindows);
}
