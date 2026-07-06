import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kirakara_app/domain/media_asset.dart';
import 'package:kirakara_app/domain/playback_state.dart';
import 'package:kirakara_app/services/display_manager.dart';
import 'package:kirakara_app/services/lan_server.dart';
import 'package:kirakara_app/services/native_window_service.dart';
import 'package:kirakara_app/services/playback_service.dart';
import 'package:kirakara_app/services/queue_service.dart';
import 'package:kirakara_app/services/search_service.dart';

class _FakeNativeWindowService extends NativeWindowService {
  const _FakeNativeWindowService(this.displays);

  final List<Map<String, Object?>> displays;

  @override
  Future<List<Map<String, Object?>>> getDisplays() async => displays;
}

void main() {
  test('queue and playback services keep room state locally', () {
    final search = SearchService();
    final queue = QueueService();
    for (final song in search.featuredSongs.take(2)) {
      queue.addSong(song);
    }

    final first = queue.takeNext();
    final playback = PlaybackService(
      queueService: queue,
      initialItem: first,
    );
    addTearDown(playback.disposeService);

    expect(playback.state.currentSong?.id, first?.song.id);
    expect(queue.items.length, 1);

    playback.play();
    expect(playback.state.mode, PlaybackMode.playing);

    playback.next();
    expect(playback.state.currentSong?.id, search.featuredSongs[1].id);
    expect(queue.items, isEmpty);

    playback.toggleAudioTrack();
    expect(playback.state.audioTrackMode, AudioTrackMode.accompaniment);
  });

  test('starting a queued song consumes it instead of duplicating up next', () {
    final search = SearchService();
    final queue = QueueService();
    final playback = PlaybackService(queueService: queue);
    addTearDown(playback.disposeService);

    final item = queue.addSong(search.featuredSongs.first);
    playback.setCurrentFromQueue(item, startPlaying: true);

    expect(playback.state.currentItem?.id, item.id);
    expect(playback.state.upNext, isNull);
    expect(queue.items, isEmpty);
  });

  test('starting a bumped song consumes it instead of duplicating up next', () {
    final search = SearchService();
    final queue = QueueService();
    final playback = PlaybackService(queueService: queue);
    addTearDown(playback.disposeService);

    final item = queue.bumpToNext(search.featuredSongs.first);
    playback.setCurrentFromQueue(item, startPlaying: true);

    expect(playback.state.currentItem?.id, item.id);
    expect(playback.state.upNext, isNull);
    expect(queue.items, isEmpty);
  });

  test('advancing to the final queued song clears stale up next', () {
    final search = SearchService();
    final queue = QueueService();
    for (final song in search.featuredSongs.take(2)) {
      queue.addSong(song);
    }

    final first = queue.takeNext();
    final playback = PlaybackService(
      queueService: queue,
      initialItem: first,
    );
    addTearDown(playback.disposeService);

    playback.refreshUpNext();
    expect(playback.state.upNext?.song.id, search.featuredSongs[1].id);

    playback.next();
    expect(playback.state.currentSong?.id, search.featuredSongs[1].id);
    expect(playback.state.upNext, isNull);
    expect(queue.items, isEmpty);
  });

  test('refreshing up next clears stale value when queue becomes empty', () {
    final search = SearchService();
    final queue = QueueService();
    for (final song in search.featuredSongs.take(2)) {
      queue.addSong(song);
    }

    final first = queue.takeNext();
    final playback = PlaybackService(
      queueService: queue,
      initialItem: first,
    );
    addTearDown(playback.disposeService);

    playback.refreshUpNext();
    final staleUpNext = playback.state.upNext;
    expect(staleUpNext, isNotNull);

    queue.remove(staleUpNext!.id);
    playback.refreshUpNext();
    expect(playback.state.upNext, isNull);
  });

  test('agony sample is searchable and backed by local media files', () {
    final search = SearchService();

    final byTitle = search.searchSongs('agony');
    expect(byTitle.single.id, 'song-local-agony');
    expect(search.searchSongs('KOTOKO').map((song) => song.id),
        contains('song-local-agony'));
    expect(search.searchSongs('神无月的巫女').map((song) => song.id),
        contains('song-local-agony'));

    final song = byTitle.single;
    expect(song.artist.name, 'KOTOKO');
    expect(song.category, '动画');
    expect(song.tags, contains('神無月の巫女'));

    for (final type in [
      MediaAssetType.video,
      MediaAssetType.vocal,
      MediaAssetType.accompaniment,
      MediaAssetType.lyric,
    ]) {
      final asset = song.assets.singleWhere((asset) => asset.type == type);
      expect(asset.cachedPath, isNotNull);
      expect(File(asset.cachedPath!).existsSync(), isTrue);
    }
    expect(File(song.lyricProject.cachedPath!).existsSync(), isTrue);
  });

  test('LAN search returns catalog index without duration metadata', () async {
    final search = SearchService();
    final queue = QueueService();
    final server = LanServer(queueService: queue, searchService: search);
    addTearDown(server.stop);

    await server.start(port: 0);
    final uri = Uri.parse(
      'http://127.0.0.1:${server.localUri!.port}/api/search?q=agony',
    );
    final request = await HttpClient().getUrl(uri);
    final response = await request.close();
    final body = await utf8.decoder.bind(response).join();
    final payload = jsonDecode(body) as List<dynamic>;
    final song = payload.single as Map<String, dynamic>;

    expect(song['id'], 'song-local-agony');
    expect(song.containsKey('durationSeconds'), isFalse);
  });

  test('display manager selects the first non-primary display as stage',
      () async {
    final displayManager = DisplayManager(
      nativeWindowService: const _FakeNativeWindowService([
        {
          'id': r'\\.\DISPLAY1',
          'name': '主显示器',
          'isPrimary': true,
          'left': 0,
          'top': 0,
          'width': 1920,
          'height': 1080,
        },
        {
          'id': r'\\.\DISPLAY2',
          'name': '虚拟舞台屏',
          'isPrimary': false,
          'left': 1920,
          'top': 0,
          'width': 1920,
          'height': 1080,
        },
      ]),
    );

    await displayManager.detectDisplays();

    expect(displayManager.hasPhysicalStageDisplay, isTrue);
    expect(displayManager.stageDisplay?.id, r'\\.\DISPLAY2');
    expect(displayManager.stageDisplay?.left, 1920);
    expect(displayManager.stageDisplay?.sizeLabel, '1920x1080');
  });
}
