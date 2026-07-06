import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kirakara_app/data/local_db/local_database.dart';
import 'package:kirakara_app/domain/playback_state.dart';
import 'package:kirakara_app/services/display_manager.dart';
import 'package:kirakara_app/services/lan_server.dart';
import 'package:kirakara_app/services/native_window_service.dart';
import 'package:kirakara_app/services/playback_service.dart';
import 'package:kirakara_app/services/queue_service.dart';
import 'package:kirakara_app/services/search_service.dart';

/// 种子 3 首测试歌曲到内存 DB。
SearchService _testSearch() {
  final db = LocalDatabase(dbPath: ':memory:');
  db.open();
  _seedTestData(db);
  return SearchService(db: db)..invalidateCache();
}

void _seedTestData(LocalDatabase db) {
  db.db.execute("INSERT INTO songs (id, title, artist_line) VALUES ('20001', 'Qi Feng', 'Nanatsukaze')");
  db.db.execute("INSERT INTO songs (id, title, artist_line) VALUES ('20002', 'Ikari', 'Kanzaki Iori')");
  db.db.execute("INSERT INTO songs (id, title, artist_line) VALUES ('20003', 'agony', 'KOTOKO')");
  db.db.execute("INSERT INTO song_tags (song_id, tag) VALUES ('20001', 'JP')");
  db.db.execute("INSERT INTO song_tags (song_id, tag) VALUES ('20002', 'VOCALOID')");
  db.db.execute("INSERT INTO song_tags (song_id, tag) VALUES ('20003', 'Anime')");
  db.db.execute("INSERT INTO song_tags (song_id, tag) VALUES ('20003', 'KRL')");
  db.db.execute("INSERT INTO categories (id, type, name, note) VALUES ('101', 'song', 'Jpop', 'JP Pop')");
  db.db.execute("INSERT INTO song_categories (song_id, category_id) VALUES ('20001', '101')");
  db.db.execute("INSERT INTO song_categories (song_id, category_id) VALUES ('20003', '101')");
}

class _FakeNativeWindowService extends NativeWindowService {
  const _FakeNativeWindowService(this.displays);

  final List<Map<String, Object?>> displays;

  @override
  Future<List<Map<String, Object?>>> getDisplays() async => displays;
}

void main() {
  test('queue and playback services keep room state locally', () {
    final search = _testSearch();
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
    final search = _testSearch();
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
    final search = _testSearch();
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
    final search = _testSearch();
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
    final search = _testSearch();
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

  test('agony sample is searchable from fallback catalog', () {
    final search = _testSearch();

    final byTitle = search.searchSongs('agony');
    expect(byTitle.single.id, '20003');
    expect(search.searchSongs('KOTOKO').map((song) => song.id),
        contains('20003'));

    final song = byTitle.single;
    expect(song.artist.name, 'KOTOKO');
    expect(song.category, 'Jpop');
    expect(song.tags, contains('KRL'));
  });

  test('LAN search returns catalog index without duration metadata', () async {
    final search = _testSearch();
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

    expect(song['id'], '20003');
    expect(song.containsKey('durationSeconds'), isFalse);
  });

  test('display manager selects the first non-primary display as stage',
      () async {
    final displayManager = DisplayManager(
      nativeWindowService: const _FakeNativeWindowService([
        {
          'id': r'\\.\DISPLAY1',
          'name': '涓绘樉绀哄櫒',
          'isPrimary': true,
          'left': 0,
          'top': 0,
          'width': 1920,
          'height': 1080,
        },
        {
          'id': r'\\.\DISPLAY2',
          'name': 'virtual stage',
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
