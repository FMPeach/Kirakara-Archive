import '../domain/artist.dart';
import '../domain/lyric_project.dart';
import '../domain/media_asset.dart';
import '../domain/song.dart';

class SearchService {
  SearchService() : _songs = _mockSongs;

  final List<Song> _songs;

  List<Song> get featuredSongs => List.unmodifiable(_songs);

  List<ArtistSummary> get artists => List.unmodifiable(_artistSummaries);

  List<CategorySummary> get categories => List.unmodifiable(_categorySummaries);

  Future<List<Song>> search(String query) async {
    return searchSongs(query);
  }

  List<Song> searchSongs(String query, {Iterable<Song>? source}) {
    final normalized = query.trim().toLowerCase();
    final pool = source ?? _songs;
    if (normalized.isEmpty) {
      return List.unmodifiable(pool);
    }

    return pool.where((song) {
      final fields = <String>[
        song.title,
        song.artist.name,
        song.category,
        if (song.code != null) song.code!,
        ...song.tags,
      ].join(' ').toLowerCase();
      return fields.contains(normalized);
    }).toList(growable: false);
  }

  List<ArtistSummary> searchArtists(String query, {String category = '全部'}) {
    final normalized = query.trim().toLowerCase();
    return _artistSummaries.where((artist) {
      final categoryOk = category == '全部' || artist.group == category;
      final searchOk = normalized.isEmpty ||
          [
            artist.name,
            artist.type,
            artist.group,
            artist.note,
          ].join(' ').toLowerCase().contains(normalized);
      return categoryOk && searchOk;
    }).toList(growable: false);
  }

  List<Song> songsForArtist(ArtistSummary artist, {String query = ''}) {
    final artistSongs = _songs.where((song) => song.artist.id == artist.id);
    return searchSongs(query, source: artistSongs);
  }

  List<Song> songsForCategory(CategorySummary category, {String query = ''}) {
    final categorySongs = category.name == '热门'
        ? _songs.take(6)
        : _songs.where((song) => song.category == category.name);
    return searchSongs(query, source: categorySongs);
  }

  int songCountForArtist(ArtistSummary artist) {
    return _songs.where((song) => song.artist.id == artist.id).length;
  }
}

class ArtistSummary {
  const ArtistSummary({
    required this.id,
    required this.name,
    required this.type,
    required this.group,
    required this.note,
  });

  final String id;
  final String name;
  final String type;
  final String group;
  final String note;
}

class CategorySummary {
  const CategorySummary({
    required this.name,
    required this.note,
  });

  final String name;
  final String note;
}

const _artistRyoku = Artist(id: 'artist-ryoku', name: '緑黄色社会');
const _artistAlstroemeria = Artist(
  id: 'artist-alstroemeria',
  name: 'Alstroemeria Records',
);
const _artistNoz = Artist(
  id: 'artist-noz',
  name: 'Noz feat. カンザキイオリ',
);
const _artistKanzaki = Artist(id: 'artist-kanzaki', name: 'カンザキイオリ');
const _artistYoko = Artist(id: 'artist-yoko', name: '高橋洋子');
const _artistFripSide = Artist(id: 'artist-fripside', name: 'fripSide');
const _artistHaruhi = Artist(id: 'artist-haruhi', name: '涼宮ハルヒ');
const _artistJay = Artist(id: 'artist-jay', name: '周杰伦');
const _artistGem = Artist(id: 'artist-gem', name: '邓紫棋');
const _artistTaylor = Artist(id: 'artist-taylor', name: 'Taylor Swift');
const _artistSuisei = Artist(id: 'artist-suisei', name: '星街すいせい');
const _artistNanatsukaze = Artist(id: 'artist-nanatsukaze', name: 'ナナツカゼ');
const _artistIkariVocaloid = Artist(
  id: 'artist-ikari-vocaloid',
  name: 'カンザキイオリ; Noz.; 初音ミク; 鏡音リン',
);

const _localMediaRoot = r'D:\Kirakara-App-ascii\media\library';

const List<ArtistSummary> _artistSummaries = [
  ArtistSummary(
    id: 'artist-ryoku',
    name: '緑黄色社会',
    type: '乐队',
    group: '日本歌手/组合',
    note: '动画 / 流行',
  ),
  ArtistSummary(
    id: 'artist-alstroemeria',
    name: 'Alstroemeria Records',
    type: '社团',
    group: '同人社团',
    note: '东方 / 同人',
  ),
  ArtistSummary(
    id: 'artist-noz',
    name: 'Noz feat. カンザキイオリ',
    type: '创作者',
    group: 'VOCALOID 声库',
    note: 'VOCALOID',
  ),
  ArtistSummary(
    id: 'artist-kanzaki',
    name: 'カンザキイオリ',
    type: '创作者',
    group: 'VOCALOID 声库',
    note: 'VOCALOID',
  ),
  ArtistSummary(
    id: 'artist-yoko',
    name: '高橋洋子',
    type: '歌手',
    group: '日本歌手/组合',
    note: '经典动画',
  ),
  ArtistSummary(
    id: 'artist-fripside',
    name: 'fripSide',
    type: '组合',
    group: '日本歌手/组合',
    note: '动画 / 电音',
  ),
  ArtistSummary(
    id: 'artist-haruhi',
    name: '涼宮ハルヒ',
    type: '角色',
    group: 'ACG 特别分类',
    note: '角色歌',
  ),
  ArtistSummary(
    id: 'artist-jay',
    name: '周杰伦',
    type: '歌手',
    group: '华语男歌手',
    note: '华语流行',
  ),
  ArtistSummary(
    id: 'artist-gem',
    name: '邓紫棋',
    type: '歌手',
    group: '华语女歌手',
    note: '华语流行',
  ),
  ArtistSummary(
    id: 'artist-taylor',
    name: 'Taylor Swift',
    type: '歌手',
    group: '欧美歌手',
    note: '欧美流行',
  ),
  ArtistSummary(
    id: 'artist-suisei',
    name: '星街すいせい',
    type: 'Vtuber',
    group: 'Vtuber / 虚拟主播',
    note: '虚拟主播',
  ),
  ArtistSummary(
    id: 'artist-nanatsukaze',
    name: 'ナナツカゼ',
    type: '歌手',
    group: '日本歌手/组合',
    note: '本地 KRL / 实机测试',
  ),
  ArtistSummary(
    id: 'artist-ikari-vocaloid',
    name: 'カンザキイオリ; Noz.; 初音ミク; 鏡音リン',
    type: '创作者',
    group: 'VOCALOID 声库',
    note: 'VOCALOID / 本地 KRL',
  ),
];

const List<CategorySummary> _categorySummaries = [
  CategorySummary(name: '热门', note: '最近常点与推荐曲目'),
  CategorySummary(name: '动画', note: '番剧 OP / ED / 插曲'),
  CategorySummary(name: 'VOCALOID', note: '术力口与创作者曲目'),
  CategorySummary(name: '东方', note: '东方同人与社团作品'),
  CategorySummary(name: '经典', note: '年代曲与包厢常备曲'),
  CategorySummary(name: '角色歌', note: '角色名义演唱曲目'),
  CategorySummary(name: '本地实机', note: '本机媒体文件与 KiraKara-Show 测试'),
];

final List<Song> _mockSongs = [
  Song(
    id: 'song-local-nanatsukaze',
    title: '七ツ風',
    artist: _artistNanatsukaze,
    duration: const Duration(minutes: 4, seconds: 14, milliseconds: 333),
    category: '本地实机',
    code: '20001',
    tags: const [
      'ナナツカゼ',
      '七ツ風',
      '七风',
      'Nanatsukaze',
      '日文',
      'KRL',
      '本地',
    ],
    coverColor: 0xff14bfd0,
    assets: _localAssets('song-local-nanatsukaze', 'nanatsukaze'),
    lyricProject: _localLyric('song-local-nanatsukaze', 'nanatsukaze'),
  ),
  Song(
    id: 'song-local-ikari',
    title: '怒り[VOCALOID ver.] (feat. Noz.)',
    artist: _artistIkariVocaloid,
    duration: const Duration(minutes: 3, seconds: 41, milliseconds: 772),
    category: 'VOCALOID',
    code: '20002',
    tags: const [
      '怒り',
      '愤怒',
      'ikari',
      'VOCALOID',
      '初音ミク',
      '鏡音リン',
      'Noz',
      'カンザキイオリ',
      'KRL',
      '本地',
    ],
    coverColor: 0xffe95895,
    assets: _localAssets('song-local-ikari', 'ikari'),
    lyricProject: _localLyric('song-local-ikari', 'ikari'),
  ),
  Song(
    id: 'song-001',
    title: '痛みに慣れてるフリしていた',
    artist: _artistRyoku,
    duration: const Duration(minutes: 5, seconds: 12),
    category: '动画',
    code: '10001',
    tags: const ['日文', '热门', '乐队', '流行', 'KRL'],
    coverColor: 0xffdd3e38,
    assets: _mockAssets('song-001'),
    lyricProject: _mockLyric('song-001'),
  ),
  Song(
    id: 'song-002',
    title: '流れる涙は',
    artist: _artistAlstroemeria,
    duration: const Duration(minutes: 4, seconds: 36),
    category: '东方',
    code: '10002',
    tags: const ['东方', '社团', '排行榜'],
    coverColor: 0xff3277f2,
    assets: _mockAssets('song-002'),
    lyricProject: _mockLyric('song-002'),
  ),
  Song(
    id: 'song-003',
    title: '怒り',
    artist: _artistNoz,
    duration: const Duration(minutes: 3, seconds: 58),
    category: 'VOCALOID',
    code: '10003',
    tags: const ['VOCALOID', '创作者', '新歌'],
    coverColor: 0xffe95895,
    assets: _mockAssets('song-003'),
    lyricProject: _mockLyric('song-003'),
  ),
  Song(
    id: 'song-004',
    title: '花になって',
    artist: _artistRyoku,
    duration: const Duration(minutes: 4, seconds: 21),
    category: '动画',
    code: '10004',
    tags: const ['动画', '乐队', '收藏'],
    coverColor: 0xff14bfd0,
    assets: _mockAssets('song-004'),
    lyricProject: _mockLyric('song-004'),
  ),
  Song(
    id: 'song-005',
    title: 'Bad Apple!!',
    artist: _artistAlstroemeria,
    duration: const Duration(minutes: 5, seconds: 17),
    category: '东方',
    code: '10005',
    tags: const ['东方', '同人', '经典'],
    coverColor: 0xff4c36b8,
    assets: _mockAssets('song-005'),
    lyricProject: _mockLyric('song-005'),
  ),
  Song(
    id: 'song-006',
    title: '命に嫌われている。',
    artist: _artistKanzaki,
    duration: const Duration(minutes: 4, seconds: 33),
    category: 'VOCALOID',
    code: '10006',
    tags: const ['VOCALOID', '创作者', '高音'],
    coverColor: 0xffe95895,
    assets: _mockAssets('song-006'),
    lyricProject: _mockLyric('song-006'),
  ),
  Song(
    id: 'song-007',
    title: '残酷な天使のテーゼ',
    artist: _artistYoko,
    duration: const Duration(minutes: 4, seconds: 5),
    category: '经典',
    code: '10007',
    tags: const ['动画', '经典', '包厢常备'],
    coverColor: 0xffdc7a32,
    assets: _mockAssets('song-007'),
    lyricProject: _mockLyric('song-007'),
  ),
  Song(
    id: 'song-008',
    title: 'only my railgun',
    artist: _artistFripSide,
    duration: const Duration(minutes: 4, seconds: 14),
    category: '动画',
    code: '10008',
    tags: const ['动画', '电音', '组合'],
    coverColor: 0xff3277f2,
    assets: _mockAssets('song-008'),
    lyricProject: _mockLyric('song-008'),
  ),
  Song(
    id: 'song-009',
    title: 'God knows...',
    artist: _artistHaruhi,
    duration: const Duration(minutes: 4, seconds: 40),
    category: '角色歌',
    code: '10009',
    tags: const ['角色歌', '动画', 'ACG'],
    coverColor: 0xffe95895,
    assets: _mockAssets('song-009'),
    lyricProject: _mockLyric('song-009'),
  ),
  Song(
    id: 'song-010',
    title: '七里香',
    artist: _artistJay,
    duration: const Duration(minutes: 4, seconds: 59),
    category: '华语',
    code: '10010',
    tags: const ['华语', '男歌手', '流行'],
    coverColor: 0xffdc7a32,
    assets: _mockAssets('song-010'),
    lyricProject: _mockLyric('song-010'),
  ),
  Song(
    id: 'song-011',
    title: '光年之外',
    artist: _artistGem,
    duration: const Duration(minutes: 3, seconds: 55),
    category: '华语',
    code: '10011',
    tags: const ['华语', '女歌手', '流行'],
    coverColor: 0xff14bfd0,
    assets: _mockAssets('song-011'),
    lyricProject: _mockLyric('song-011'),
  ),
  Song(
    id: 'song-012',
    title: 'Anti-Hero',
    artist: _artistTaylor,
    duration: const Duration(minutes: 3, seconds: 21),
    category: '欧美',
    code: '10012',
    tags: const ['欧美', '流行', '英文'],
    coverColor: 0xff3277f2,
    assets: _mockAssets('song-012'),
    lyricProject: _mockLyric('song-012'),
  ),
  Song(
    id: 'song-013',
    title: 'Stellar Stellar',
    artist: _artistSuisei,
    duration: const Duration(minutes: 5, seconds: 2),
    category: 'Vtuber',
    code: '10013',
    tags: const ['Vtuber', '虚拟主播', '日文'],
    coverColor: 0xff4c36b8,
    assets: _mockAssets('song-013'),
    lyricProject: _mockLyric('song-013'),
  ),
];

List<MediaAsset> _mockAssets(String songId) {
  return [
    MediaAsset(
      id: '$songId-video',
      type: MediaAssetType.video,
      uri: Uri.parse('kirakara://mock/media/$songId/video.mp4'),
    ),
    MediaAsset(
      id: '$songId-cover',
      type: MediaAssetType.cover,
      uri: Uri.parse('kirakara://mock/media/$songId/cover.jpg'),
    ),
  ];
}

List<MediaAsset> _localAssets(String songId, String mediaDir) {
  final base = '$_localMediaRoot\\$mediaDir';
  return [
    _fileAsset(
      id: '$songId-video',
      type: MediaAssetType.video,
      path: '$base\\background.mp4',
    ),
    _fileAsset(
      id: '$songId-vocal',
      type: MediaAssetType.vocal,
      path: '$base\\vocal.wav',
    ),
    _fileAsset(
      id: '$songId-accompaniment',
      type: MediaAssetType.accompaniment,
      path: '$base\\accompaniment.wav',
    ),
    _fileAsset(
      id: '$songId-lyric',
      type: MediaAssetType.lyric,
      path: '$base\\lyrics.krl',
    ),
  ];
}

MediaAsset _fileAsset({
  required String id,
  required MediaAssetType type,
  required String path,
}) {
  return MediaAsset(
    id: id,
    type: type,
    uri: Uri.file(path),
    cachedPath: path,
  );
}

LyricProject _mockLyric(String songId) {
  return LyricProject(
    id: '$songId-krl',
    songId: songId,
    krlUri: Uri.parse('kirakara://mock/krl/$songId.krl'),
    version: 1,
  );
}

LyricProject _localLyric(String songId, String mediaDir) {
  final path = '$_localMediaRoot\\$mediaDir\\lyrics.krl';
  return LyricProject(
    id: '$songId-krl',
    songId: songId,
    krlUri: Uri.file(path),
    version: 1,
    cachedPath: path,
  );
}
