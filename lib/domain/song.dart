import 'artist.dart';
import 'lyric_project.dart';
import 'media_asset.dart';

class Song {
  const Song({
    required this.id,
    required this.title,
    required this.category,
    required this.assets,
    this.artist,
    this.lyricProject,
    this.duration,
    this.code,
    this.tags = const [],
    this.coverColor = 0xffdd3e38,
    this.isExternal = false,
  });

  final String id;
  final String title;
  final Artist? artist;
  final Duration? duration;
  final String category;
  final List<MediaAsset> assets;
  final LyricProject? lyricProject;
  final String? code;
  final List<String> tags;
  final int coverColor;
  final bool isExternal;

  /// 外部歌曲（如 B站 DLNA 投屏）：纯视频，无歌词，无原唱/伴奏切换。
  bool get isExternalSong => isExternal;
}
