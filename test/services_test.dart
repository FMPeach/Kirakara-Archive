import 'package:flutter_test/flutter_test.dart';
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
}
