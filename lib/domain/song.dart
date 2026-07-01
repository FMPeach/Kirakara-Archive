import 'artist.dart';
import 'lyric_project.dart';
import 'media_asset.dart';

class Song {
  const Song({
    required this.id,
    required this.title,
    required this.artist,
    required this.duration,
    required this.category,
    required this.assets,
    required this.lyricProject,
    this.code,
    this.tags = const [],
    this.coverColor = 0xffdd3e38,
  });

  final String id;
  final String title;
  final Artist artist;
  final Duration duration;
  final String category;
  final List<MediaAsset> assets;
  final LyricProject lyricProject;
  final String? code;
  final List<String> tags;
  final int coverColor;
}
