import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:kirakara_app/data/local_db/local_database.dart';
import 'package:kirakara_app/domain/lyric_project.dart';
import 'package:kirakara_app/domain/media_asset.dart';
import 'package:kirakara_app/domain/playback_state.dart';
import 'package:kirakara_app/domain/song.dart';
import 'package:kirakara_app/services/display_manager.dart';
import 'package:kirakara_app/services/lan_server.dart';
import 'package:kirakara_app/services/native_window_service.dart';
import 'package:kirakara_app/services/playback_asset_cache.dart';
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
  db.db.execute(
      "INSERT INTO songs (id, title, artist_line) VALUES ('20001', 'Qi Feng', 'Nanatsukaze')");
  db.db.execute(
      "INSERT INTO songs (id, title, artist_line) VALUES ('20002', 'Ikari', 'Kanzaki Iori')");
  db.db.execute(
      "INSERT INTO songs (id, title, artist_line) VALUES ('20003', 'agony', 'KOTOKO')");
  db.db.execute("INSERT INTO song_tags (song_id, tag) VALUES ('20001', 'JP')");
  db.db.execute(
      "INSERT INTO song_tags (song_id, tag) VALUES ('20002', 'VOCALOID')");
  db.db.execute(
      "INSERT INTO song_tags (song_id, tag) VALUES ('20003', 'Anime')");
  db.db.execute("INSERT INTO song_tags (song_id, tag) VALUES ('20003', 'KRL')");
  db.db.execute(
      "INSERT INTO categories (id, type, name, note) VALUES ('101', 'song', 'Jpop', 'JP Pop')");
  db.db.execute(
      "INSERT INTO song_categories (song_id, category_id) VALUES ('20001', '101')");
  db.db.execute(
      "INSERT INTO song_categories (song_id, category_id) VALUES ('20003', '101')");
}

class _FakeNativeWindowService extends NativeWindowService {
  const _FakeNativeWindowService(this.displays);

  final List<Map<String, Object?>> displays;

  @override
  Future<List<Map<String, Object?>>> getDisplays() async => displays;
}

class _FakeAssetHttpClient extends http.BaseClient {
  _FakeAssetHttpClient({
    this.videoStarted,
    this.releaseVideo,
    this.audioStarted,
    this.releaseAudio,
    this.accompanimentStarted,
    this.releaseAccompaniment,
    this.videoTotalLength = 4,
  });

  final Completer<void>? videoStarted;
  final Completer<void>? releaseVideo;
  final Completer<void>? audioStarted;
  final Completer<void>? releaseAudio;
  final Completer<void>? accompanimentStarted;
  final Completer<void>? releaseAccompaniment;
  final int videoTotalLength;
  int fullVideoRequests = 0;
  int notFoundRequests = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path;
    if (path == '/media/video.mp4') {
      final range = request.headers[HttpHeaders.rangeHeader];
      if (range != null) {
        final match = RegExp(r'bytes=(\d+)-(\d*)').firstMatch(range);
        final start = match == null ? 0 : int.parse(match.group(1)!);
        final endText = match?.group(2) ?? '';
        final end = endText.isEmpty ? start + 3 : int.parse(endText);
        final length = end - start + 1;
        return http.StreamedResponse(
          Stream.value(List<int>.filled(length, 9)),
          HttpStatus.partialContent,
          contentLength: length,
          headers: {
            HttpHeaders.acceptRangesHeader: 'bytes',
            HttpHeaders.contentLengthHeader: '$length',
            HttpHeaders.contentRangeHeader:
                'bytes $start-$end/$videoTotalLength',
          },
        );
      }
      fullVideoRequests++;
      if (videoStarted != null && !videoStarted!.isCompleted) {
        videoStarted!.complete();
      }
      final controller = StreamController<List<int>>();
      unawaited(() async {
        controller.add([1, 2]);
        final gate = releaseVideo;
        if (gate != null) {
          await gate.future;
        }
        controller.add([3, 4]);
        await controller.close();
      }());
      return http.StreamedResponse(
        controller.stream,
        HttpStatus.ok,
        contentLength: videoTotalLength,
        headers: {HttpHeaders.contentLengthHeader: '$videoTotalLength'},
      );
    }
    if (path == '/media/vocal.m4a') {
      if (audioStarted != null && !audioStarted!.isCompleted) {
        audioStarted!.complete();
      }
      final controller = StreamController<List<int>>();
      unawaited(() async {
        final gate = releaseAudio;
        if (gate != null) await gate.future;
        controller.add([5, 6, 7]);
        await controller.close();
      }());
      return http.StreamedResponse(
        controller.stream,
        HttpStatus.ok,
        contentLength: 3,
        headers: {HttpHeaders.contentLengthHeader: '3'},
      );
    }
    if (path == '/media/inst.m4a') {
      if (accompanimentStarted != null && !accompanimentStarted!.isCompleted) {
        accompanimentStarted!.complete();
      }
      final controller = StreamController<List<int>>();
      unawaited(() async {
        final gate = releaseAccompaniment;
        if (gate != null) await gate.future;
        controller.add([8, 9, 10]);
        await controller.close();
      }());
      return http.StreamedResponse(
        controller.stream,
        HttpStatus.ok,
        contentLength: 3,
        headers: {HttpHeaders.contentLengthHeader: '3'},
      );
    }
    if (path == '/media/lyrics.krl') {
      return http.StreamedResponse(
        Stream.value('krl'.codeUnits),
        HttpStatus.ok,
        contentLength: 3,
        headers: {HttpHeaders.contentLengthHeader: '3'},
      );
    }
    notFoundRequests++;
    return http.StreamedResponse(
      const Stream<List<int>>.empty(),
      HttpStatus.notFound,
    );
  }
}

class _ConcurrentVideoHttpClient extends http.BaseClient {
  final List<Completer<void>> started =
      List.generate(4, (_) => Completer<void>());
  final List<Completer<void>> release =
      List.generate(4, (_) => Completer<void>());
  int active = 0;
  int maxActive = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final match =
        RegExp(r'/media/video(\d+)\.mp4$').firstMatch(request.url.path);
    if (match == null) {
      return http.StreamedResponse(
        Stream.value([1]),
        HttpStatus.ok,
        contentLength: 1,
        headers: {HttpHeaders.contentLengthHeader: '1'},
      );
    }

    final index = int.parse(match.group(1)!);
    active++;
    if (active > maxActive) maxActive = active;
    if (!started[index].isCompleted) started[index].complete();

    final controller = StreamController<List<int>>();
    unawaited(() async {
      await release[index].future;
      controller.add([index, index + 1]);
      await controller.close();
      active--;
    }());

    return http.StreamedResponse(
      controller.stream,
      HttpStatus.ok,
      contentLength: 2,
      headers: {HttpHeaders.contentLengthHeader: '2'},
    );
  }
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

  test('starting an empty-room song does not notify the queue', () {
    final search = _testSearch();
    final queue = QueueService();
    var queueNotifications = 0;
    queue.addListener(() => queueNotifications++);
    final playback = PlaybackService(queueService: queue);
    addTearDown(playback.disposeService);

    playback.setCurrentSong(search.featuredSongs.first, startPlaying: true);

    expect(playback.state.currentSong?.id, search.featuredSongs.first.id);
    expect(playback.state.isPlaying, isTrue);
    expect(queue.items, isEmpty);
    expect(queueNotifications, 0);
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
    expect(
        search.searchSongs('KOTOKO').map((song) => song.id), contains('20003'));

    final song = byTitle.single;
    expect(song.artist?.name, 'KOTOKO');
    expect(song.category, 'Jpop');
    expect(song.tags, contains('KRL'));
  });

  test('LAN search returns catalog index without duration metadata', () async {
    final search = _testSearch();
    final queue = QueueService();
    final playback = PlaybackService(queueService: queue);
    final server = LanServer(
      queueService: queue,
      searchService: search,
      playbackService: playback,
    );
    addTearDown(playback.disposeService);
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

  test('playback cache scopes a custom root to the current app session',
      () async {
    final cacheRoot =
        await Directory.systemTemp.createTemp('kirakara_cache_root_test_');
    final marker = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}'
      'kirakara_cache_session_$pid.path',
    );
    final session = Directory(
      '${cacheRoot.path}${Platform.pathSeparator}session_$pid',
    );
    addTearDown(() {
      if (marker.existsSync()) marker.deleteSync();
      if (cacheRoot.existsSync()) cacheRoot.deleteSync(recursive: true);
    });

    final cache = PlaybackAssetCache(
      baseUrl: 'http://catalog.test',
      cacheRoot: cacheRoot,
    );
    addTearDown(cache.dispose);

    expect(session.existsSync(), isTrue);
    expect(marker.existsSync(), isTrue);
    expect((await marker.readAsString()).trim(), session.absolute.path);

    cache.clear();
    expect(session.existsSync(), isFalse);
    expect(marker.existsSync(), isFalse);
    expect(cacheRoot.existsSync(), isTrue);
  });

  test('playback cache waits for audio and lyrics but not video', () async {
    final videoStarted = Completer<void>();
    final releaseVideo = Completer<void>();

    final cacheDir =
        await Directory.systemTemp.createTemp('kirakara_cache_test_');
    addTearDown(() {
      if (cacheDir.existsSync()) cacheDir.deleteSync(recursive: true);
    });

    const baseUrl = 'http://catalog.test';
    final cache = PlaybackAssetCache(
      baseUrl: baseUrl,
      cacheDir: cacheDir,
      httpClient: _FakeAssetHttpClient(),
      mediaHttpClient: _FakeAssetHttpClient(
        videoStarted: videoStarted,
        releaseVideo: releaseVideo,
      ),
    );
    addTearDown(cache.dispose);

    final video = MediaAsset(
      id: 'song-video',
      type: MediaAssetType.video,
      uri: Uri.parse('/media/video.mp4'),
    );
    final vocal = MediaAsset(
      id: 'song-vocal',
      type: MediaAssetType.vocal,
      uri: Uri.parse('/media/vocal.m4a'),
    );
    final lyric = MediaAsset(
      id: 'song-krl',
      type: MediaAssetType.lyric,
      uri: Uri.parse('/media/lyrics.krl'),
    );
    final song = Song(
      id: 'song',
      title: 'Progressive',
      category: 'Test',
      assets: [video, vocal, lyric],
      lyricProject: LyricProject(
        id: 'song-krl',
        songId: 'song',
        krlUri: lyric.uri,
        version: 1,
      ),
    );

    await cache.ensurePlaybackAssets(song).timeout(
          const Duration(seconds: 1),
          onTimeout: () => fail('playback preparation waited for video'),
        );
    await videoStarted.future.timeout(
      const Duration(seconds: 1),
      onTimeout: () => fail('video prefetch was not started'),
    );

    expect(vocal.cachedPath, isNotNull);
    expect(File(vocal.cachedPath!).existsSync(), isTrue);
    expect(song.lyricProject!.cachedPath, isNotNull);
    expect(File(song.lyricProject!.cachedPath!).readAsStringSync(), 'krl');
    expect(video.cachedPath, isNull);
    final playbackUrl = cache.playbackPathFor(video);
    expect(playbackUrl, isNotNull);
    expect(playbackUrl, startsWith('http://127.0.0.1:'));

    final rangeResponse = await http.get(
      Uri.parse(playbackUrl!),
      headers: {HttpHeaders.rangeHeader: 'bytes=0-1'},
    );
    expect(rangeResponse.statusCode, HttpStatus.partialContent);
    expect(
        rangeResponse.headers[HttpHeaders.contentRangeHeader], 'bytes 0-1/4');
    expect(rangeResponse.bodyBytes, [1, 2]);

    releaseVideo.complete();
    for (var i = 0; i < 20 && video.cachedPath == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    expect(video.cachedPath, isNotNull);
    expect(File(video.cachedPath!).existsSync(), isTrue);
    expect(cache.playbackPathFor(video), startsWith('http://127.0.0.1:'));
  });

  test('playback cache starts video while required audio is still loading',
      () async {
    final videoStarted = Completer<void>();
    final releaseVideo = Completer<void>();
    final audioStarted = Completer<void>();
    final releaseAudio = Completer<void>();
    final cacheDir =
        await Directory.systemTemp.createTemp('kirakara_cache_test_');
    addTearDown(() {
      if (cacheDir.existsSync()) cacheDir.deleteSync(recursive: true);
    });
    final cache = PlaybackAssetCache(
      baseUrl: 'http://catalog.test',
      cacheDir: cacheDir,
      httpClient: _FakeAssetHttpClient(
        audioStarted: audioStarted,
        releaseAudio: releaseAudio,
      ),
      mediaHttpClient: _FakeAssetHttpClient(
        videoStarted: videoStarted,
        releaseVideo: releaseVideo,
      ),
    );
    addTearDown(cache.dispose);

    final video = MediaAsset(
      id: 'parallel-video',
      type: MediaAssetType.video,
      uri: Uri.parse('/media/video.mp4'),
    );
    final vocal = MediaAsset(
      id: 'parallel-vocal',
      type: MediaAssetType.vocal,
      uri: Uri.parse('/media/vocal.m4a'),
    );
    final lyric = MediaAsset(
      id: 'parallel-krl',
      type: MediaAssetType.lyric,
      uri: Uri.parse('/media/lyrics.krl'),
    );
    final song = Song(
      id: 'parallel-song',
      title: 'Parallel',
      category: 'Test',
      assets: [video, vocal, lyric],
      lyricProject: LyricProject(
        id: 'parallel-krl',
        songId: 'parallel-song',
        krlUri: lyric.uri,
        version: 1,
      ),
    );

    final prepare = cache.ensurePlaybackAssets(song);
    await audioStarted.future.timeout(const Duration(seconds: 1));
    await videoStarted.future.timeout(
      const Duration(seconds: 1),
      onTimeout: () => fail('video waited for the audio download to finish'),
    );

    releaseAudio.complete();
    await prepare.timeout(const Duration(seconds: 1));
    releaseVideo.complete();
    for (var i = 0; i < 20 && video.cachedPath == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    expect(video.cachedPath, isNotNull);
  });

  test('playback cache waits for both audio tracks but not video', () async {
    final releaseAccompaniment = Completer<void>();
    final accompanimentStarted = Completer<void>();
    final releaseVideo = Completer<void>();
    final cacheDir =
        await Directory.systemTemp.createTemp('kirakara_cache_test_');
    addTearDown(() {
      if (cacheDir.existsSync()) cacheDir.deleteSync(recursive: true);
    });
    final cache = PlaybackAssetCache(
      baseUrl: 'http://catalog.test',
      cacheDir: cacheDir,
      httpClient: _FakeAssetHttpClient(
        accompanimentStarted: accompanimentStarted,
        releaseAccompaniment: releaseAccompaniment,
      ),
      mediaHttpClient: _FakeAssetHttpClient(
        releaseVideo: releaseVideo,
      ),
    );
    addTearDown(cache.dispose);

    final video = MediaAsset(
      id: 'selected-video',
      type: MediaAssetType.video,
      uri: Uri.parse('/media/video.mp4'),
    );
    final vocal = MediaAsset(
      id: 'selected-vocal',
      type: MediaAssetType.vocal,
      uri: Uri.parse('/media/vocal.m4a'),
    );
    final accompaniment = MediaAsset(
      id: 'selected-inst',
      type: MediaAssetType.accompaniment,
      uri: Uri.parse('/media/inst.m4a'),
    );
    final lyric = MediaAsset(
      id: 'selected-krl',
      type: MediaAssetType.lyric,
      uri: Uri.parse('/media/lyrics.krl'),
    );
    final song = Song(
      id: 'selected-song',
      title: 'Selected Track',
      category: 'Test',
      assets: [video, vocal, accompaniment, lyric],
      lyricProject: LyricProject(
        id: 'selected-krl',
        songId: 'selected-song',
        krlUri: lyric.uri,
        version: 1,
      ),
    );

    var completed = false;
    final prepare = cache.ensurePlaybackAssets(song).then((_) {
      completed = true;
    });
    await accompanimentStarted.future.timeout(const Duration(seconds: 1));

    String? playbackUrl;
    for (var i = 0; i < 20; i++) {
      playbackUrl = cache.playbackPathFor(video);
      if (playbackUrl != null && playbackUrl.startsWith('http://127.0.0.1:')) {
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }

    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(completed, isFalse);
    expect(vocal.cachedPath, isNotNull);
    expect(accompaniment.cachedPath, isNull);
    expect(playbackUrl, startsWith('http://127.0.0.1:'));

    releaseAccompaniment.complete();
    await prepare.timeout(const Duration(seconds: 1));
    expect(completed, isTrue);
    expect(accompaniment.cachedPath, isNotNull);

    releaseVideo.complete();
    for (var i = 0; i < 40 && video.cachedPath == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
  });

  test('playback cache limits background video downloads to three', () async {
    final client = _ConcurrentVideoHttpClient();
    final cacheDir =
        await Directory.systemTemp.createTemp('kirakara_cache_test_');
    addTearDown(() {
      if (cacheDir.existsSync()) cacheDir.deleteSync(recursive: true);
    });
    final cache = PlaybackAssetCache(
      baseUrl: 'http://catalog.test',
      cacheDir: cacheDir,
      httpClient: client,
      mediaHttpClient: client,
    );
    addTearDown(cache.dispose);

    for (var i = 0; i < 4; i++) {
      cache.prefetchPlaybackAssets(
        Song(
          id: 'video-limit-$i',
          title: 'Video Limit $i',
          category: 'Test',
          assets: [
            MediaAsset(
              id: 'video-limit-$i',
              type: MediaAssetType.video,
              uri: Uri.parse('/media/video$i.mp4'),
            ),
          ],
        ),
      );
    }

    await Future.wait(client.started.take(3).map((c) => c.future))
        .timeout(const Duration(seconds: 1));
    expect(client.started[3].isCompleted, isFalse);
    expect(client.maxActive, 3);

    client.release[0].complete();
    await client.started[3].future.timeout(const Duration(seconds: 1));
    expect(client.maxActive, 3);

    for (var i = 1; i < 4; i++) {
      client.release[i].complete();
    }
    for (var i = 0; i < 40 && client.active > 0; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    expect(client.active, 0);
  });

  test('playback cache proxies far-ahead video ranges instead of waiting',
      () async {
    final videoStarted = Completer<void>();
    final releaseVideo = Completer<void>();

    final cacheDir =
        await Directory.systemTemp.createTemp('kirakara_cache_test_');
    addTearDown(() {
      if (cacheDir.existsSync()) cacheDir.deleteSync(recursive: true);
    });

    final cache = PlaybackAssetCache(
      baseUrl: 'http://catalog.test',
      cacheDir: cacheDir,
      httpClient: _FakeAssetHttpClient(),
      mediaHttpClient: _FakeAssetHttpClient(
        videoStarted: videoStarted,
        releaseVideo: releaseVideo,
        videoTotalLength: 1000000,
      ),
    );
    addTearDown(cache.dispose);

    final video = MediaAsset(
      id: 'long-video',
      type: MediaAssetType.video,
      uri: Uri.parse('/media/video.mp4'),
    );
    final vocal = MediaAsset(
      id: 'long-vocal',
      type: MediaAssetType.vocal,
      uri: Uri.parse('/media/vocal.m4a'),
    );
    final lyric = MediaAsset(
      id: 'long-krl',
      type: MediaAssetType.lyric,
      uri: Uri.parse('/media/lyrics.krl'),
    );
    final song = Song(
      id: 'long-song',
      title: 'Long Progressive',
      category: 'Test',
      assets: [video, vocal, lyric],
      lyricProject: LyricProject(
        id: 'long-krl',
        songId: 'long-song',
        krlUri: lyric.uri,
        version: 1,
      ),
    );

    await cache.ensurePlaybackAssets(song);
    await videoStarted.future.timeout(const Duration(seconds: 1));
    final playbackUrl = cache.playbackPathFor(video);
    expect(playbackUrl, startsWith('http://127.0.0.1:'));

    final response = await http.get(
      Uri.parse(playbackUrl!),
      headers: {HttpHeaders.rangeHeader: 'bytes=900000-900003'},
    ).timeout(
      const Duration(seconds: 1),
      onTimeout: () => fail('far-ahead video range waited for local cache'),
    );

    expect(response.statusCode, HttpStatus.partialContent);
    expect(
      response.headers[HttpHeaders.contentRangeHeader],
      'bytes 900000-900003/1000000',
    );
    expect(response.bodyBytes, [9, 9, 9, 9]);

    releaseVideo.complete();
    await Future<void>.delayed(const Duration(milliseconds: 50));
  });

  test('playback prefetch deduplicates downloads and ignores missing cover',
      () async {
    final videoStarted = Completer<void>();
    final releaseVideo = Completer<void>();
    final client = _FakeAssetHttpClient(
      videoStarted: videoStarted,
      releaseVideo: releaseVideo,
    );
    final cacheDir =
        await Directory.systemTemp.createTemp('kirakara_cache_test_');
    addTearDown(() {
      if (cacheDir.existsSync()) cacheDir.deleteSync(recursive: true);
    });
    final cache = PlaybackAssetCache(
      baseUrl: 'http://catalog.test',
      cacheDir: cacheDir,
      httpClient: client,
      mediaHttpClient: client,
    );
    addTearDown(cache.dispose);

    final video = MediaAsset(
      id: 'dedupe-video',
      type: MediaAssetType.video,
      uri: Uri.parse('/media/video.mp4'),
    );
    final vocal = MediaAsset(
      id: 'dedupe-vocal',
      type: MediaAssetType.vocal,
      uri: Uri.parse('/media/vocal.m4a'),
    );
    final lyric = MediaAsset(
      id: 'dedupe-krl',
      type: MediaAssetType.lyric,
      uri: Uri.parse('/media/lyrics.krl'),
    );
    final cover = MediaAsset(
      id: 'dedupe-cover',
      type: MediaAssetType.cover,
      uri: Uri.parse('/media/missing-cover.jpg'),
    );
    final song = Song(
      id: 'dedupe-song',
      title: 'Dedupe',
      category: 'Test',
      assets: [video, vocal, lyric, cover],
      lyricProject: LyricProject(
        id: 'dedupe-krl',
        songId: 'dedupe-song',
        krlUri: lyric.uri,
        version: 1,
      ),
    );

    cache.prefetchPlaybackAssets(song);
    cache.prefetchPlaybackAssets(song);
    await cache.ensurePlaybackAssets(song);
    await videoStarted.future.timeout(const Duration(seconds: 1));

    expect(client.fullVideoRequests, 1);
    expect(client.notFoundRequests, 1); // cover 404, handled gracefully

    releaseVideo.complete();
    for (var i = 0; i < 20 && !cache.progressForSong(song).isComplete; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    final progress = cache.progressForSong(song);
    expect(progress.assetCount, 4); // video + vocal + lyric + cover
    expect(progress.completeAssets, 4);
    expect(progress.isComplete, isTrue);
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
