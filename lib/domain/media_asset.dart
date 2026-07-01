enum MediaAssetType {
  video,
  accompaniment,
  vocal,
  cover,
  lyric,
}

class MediaAsset {
  const MediaAsset({
    required this.id,
    required this.type,
    required this.uri,
    this.version = 1,
    this.cachedPath,
  });

  final String id;
  final MediaAssetType type;
  final Uri uri;
  final int version;
  final String? cachedPath;
}
