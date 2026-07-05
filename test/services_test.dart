import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kirakara_app/domain/media_asset.dart';
import 'package:kirakara_app/domain/playback_state.dart';
import 'package:kirakara_app/services/playback_service.dart';
import 'package:kirakara_app/services/queue_service.dart';
import 'package:kirakara_app/services/search_service.dart';

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
}
