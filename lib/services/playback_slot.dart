import '../domain/song.dart';

enum SlotState { empty, preparing, ready, failed }

class PlaybackSlot {
  PlaybackSlot({required this.songId});

  final String songId;
  SlotState state = SlotState.empty;
  int generation = 0;
  Song? song;

  String? videoPath;
  String? vocalPath;
  String? instPath;
  String? krlPath;
  String? error;

  bool get isReady => state == SlotState.ready;
}
