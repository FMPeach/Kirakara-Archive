import 'package:flutter/material.dart';

import '../../domain/song.dart';
import '../../ime/ime_controller.dart';
import '../../ime/search_query_controller.dart';
import '../../services/search_service.dart';
import '../theme/kirakara_theme.dart';
import '../widgets/karaoke_input_panel.dart';

enum BrowseMode {
  songs,
  artists,
  artistDetail,
  categories,
  externalLink,
  ranking,
}

class BrowseScreen extends StatefulWidget {
  const BrowseScreen({
    super.key,
    required this.searchService,
    required this.initialMode,
    required this.onExit,
    required this.onAddSong,
    required this.onBumpSong,
    required this.onAnnouncement,
    this.initialQuery = '',
  });

  final SearchService searchService;
  final BrowseMode initialMode;
  final String initialQuery;
  final VoidCallback onExit;
  final ValueChanged<Song> onAddSong;
  final ValueChanged<Song> onBumpSong;
  final ValueChanged<String> onAnnouncement;

  @override
  State<BrowseScreen> createState() => _BrowseScreenState();
}

class _BrowseScreenState extends State<BrowseScreen> {
  late final SearchQueryController _searchQueryController;
  late final ImeController _imeController;
  final FocusNode _searchFocusNode = FocusNode(debugLabel: 'browse-search');

  late BrowseMode _mode;
  String _songQuery = '';
  String _songScope = '全部';
  String _artistQuery = '';
  String _artistCategory = '全部';
  String _artistSongQuery = '';
  String _categoryQuery = '';
  String _activeCategory = '热门';
  String _activeRanking = '热门榜';
  ArtistSummary? _activeArtist;

  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode;
    _songQuery = widget.initialQuery;
    _searchQueryController = SearchQueryController(text: _songQuery);
    _searchQueryController.addListener(_handleSearchControllerChanged);
    _imeController = ImeController(
      searchQueryController: _searchQueryController,
    );
    _syncSearchController();
  }

  @override
  void didUpdateWidget(covariant BrowseScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialMode != widget.initialMode ||
        oldWidget.initialQuery != widget.initialQuery) {
      _mode = widget.initialMode;
      _songQuery = widget.initialQuery;
      _songScope = '全部';
      _activeArtist = null;
      _syncSearchController();
    }
  }

  @override
  void dispose() {
    _searchQueryController.removeListener(_handleSearchControllerChanged);
    _imeController.dispose();
    _searchQueryController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(30, 28, 30, 22),
      child: switch (_mode) {
        BrowseMode.songs => _buildSongPage(),
        BrowseMode.artists => _buildArtistPage(),
        BrowseMode.artistDetail => _buildArtistDetailPage(),
        BrowseMode.categories => _buildCategoryPage(),
        BrowseMode.externalLink => _buildExternalLinkPage(),
        BrowseMode.ranking => _buildRankingPage(),
      },
    );
  }

  Widget _buildSongPage() {
    final songs = _scopedSongs();
    final subtitle = _songScope == '全部'
        ? (_songQuery.trim().isEmpty ? '全曲库搜索' : '搜索：$_songQuery')
        : '$_songScope 分类内搜索';
    return Row(
      children: [
        SizedBox(
          width: 420,
          child: _SongScopeRail(
            title: '搜索范围',
            options: _songScopeOptions,
            activeOption: _songScope,
            onBack: widget.onExit,
            onSelected: _handleSongScope,
          ),
        ),
        const SizedBox(width: 22),
        Expanded(
          child: _SongResultPanel(
            title: '歌名点歌',
            subtitle: subtitle,
            songs: songs,
            columns: 1,
            onAddSong: _addSong,
            onBumpSong: _bumpSong,
          ),
        ),
        const SizedBox(width: 22),
        SizedBox(
          width: 488,
          child: KaraokeInputPanel(
            activeTab: '歌名',
            placeholder: '搜索歌名、歌手、编号',
            controller: _searchQueryController.textController,
            searchFocusNode: _searchFocusNode,
            imeController: _imeController,
            onTab: _switchSearchTab,
            onSearch: _handleSearchSubmit,
          ),
        ),
      ],
    );
  }

  Widget _buildArtistPage() {
    final artists = widget.searchService.searchArtists(
      _artistQuery,
      category: _artistCategory,
    );
    final categories = [
      '全部',
      ...widget.searchService.artists.map((artist) => artist.group).toSet(),
    ];

    return Row(
      children: [
        SizedBox(
          width: 420,
          child: _OptionRail(
            title: '地区与类型',
            options: categories,
            activeOption: _artistCategory,
            onBack: widget.onExit,
            onSelected: (category) {
              setState(() => _artistCategory = category);
              widget.onAnnouncement('筛选歌手：$category');
            },
          ),
        ),
        const SizedBox(width: 22),
        Expanded(
          child: _ArtistResultPanel(
            artists: artists,
            songCountForArtist: widget.searchService.songCountForArtist,
            onArtist: _openArtist,
          ),
        ),
        const SizedBox(width: 22),
        SizedBox(
          width: 488,
          child: KaraokeInputPanel(
            activeTab: '歌手',
            placeholder: '搜索歌手、角色、社团或声库',
            controller: _searchQueryController.textController,
            searchFocusNode: _searchFocusNode,
            imeController: _imeController,
            onTab: _switchSearchTab,
            onSearch: _handleSearchSubmit,
          ),
        ),
      ],
    );
  }

  Widget _buildArtistDetailPage() {
    final artist = _activeArtist ?? widget.searchService.artists.first;
    final artistSongs = widget.searchService.songsForArtist(
      artist,
      query: _artistSongQuery,
    );
    final total = widget.searchService.songCountForArtist(artist);

    return Row(
      children: [
        SizedBox(
          width: 420,
          child: _ArtistDetailRail(
            artist: artist,
            songCount: total,
            searchController: _searchQueryController.textController,
            onBack: () {
              setState(() {
                _mode = BrowseMode.artists;
                _activeArtist = null;
                _artistSongQuery = '';
              });
              _syncSearchController();
              widget.onAnnouncement('返回：歌手点歌');
            },
            onSearchChanged: _handleSearchChanged,
          ),
        ),
        const SizedBox(width: 22),
        Expanded(
          child: _SongResultPanel(
            title: artist.name,
            subtitle: '${artist.type} · ${artist.note}',
            songs: artistSongs,
            columns: 1,
            onAddSong: _addSong,
            onBumpSong: _bumpSong,
          ),
        ),
        const SizedBox(width: 22),
        SizedBox(
          width: 488,
          child: KaraokeInputPanel(
            activeTab: '歌手内',
            tabs: const ['歌手内'],
            placeholder: '在 ${artist.name} 的歌曲中搜索',
            controller: _searchQueryController.textController,
            searchFocusNode: _searchFocusNode,
            imeController: _imeController,
            onTab: _switchSearchTab,
            onSearch: _handleSearchSubmit,
          ),
        ),
      ],
    );
  }

  Widget _buildCategoryPage() {
    final activeMeta = widget.searchService.categories.firstWhere(
      (category) => category.name == _activeCategory,
      orElse: () => widget.searchService.categories.first,
    );
    final songs = widget.searchService.songsForCategory(
      activeMeta,
      query: _categoryQuery,
    );

    return Row(
      children: [
        SizedBox(
          width: 420,
          child: _CategoryRail(
            categories: widget.searchService.categories,
            activeCategory: activeMeta.name,
            onBack: widget.onExit,
            onSelected: (category) {
              setState(() => _activeCategory = category.name);
              widget.onAnnouncement('分类点歌：${category.name}');
            },
          ),
        ),
        const SizedBox(width: 22),
        Expanded(
          child: _SongResultPanel(
            title: activeMeta.name,
            subtitle: activeMeta.note,
            songs: songs,
            columns: 1,
            onAddSong: _addSong,
            onBumpSong: _bumpSong,
          ),
        ),
        const SizedBox(width: 22),
        SizedBox(
          width: 488,
          child: KaraokeInputPanel(
            activeTab: '分类',
            placeholder: '在当前分类中搜索歌曲、歌手、编号',
            controller: _searchQueryController.textController,
            searchFocusNode: _searchFocusNode,
            imeController: _imeController,
            onTab: _switchSearchTab,
            onSearch: _handleSearchSubmit,
          ),
        ),
      ],
    );
  }

  Widget _buildExternalLinkPage() {
    return Row(
      children: [
        Expanded(
          child: _ExternalLinkPanel(onBack: widget.onExit),
        ),
        const SizedBox(width: 22),
        SizedBox(
          width: 488,
          child: KaraokeInputPanel(
            activeTab: '外链',
            tabs: const ['外链'],
            placeholder: '搜索已解析的外链歌曲',
            controller: _searchQueryController.textController,
            searchFocusNode: _searchFocusNode,
            imeController: _imeController,
            onTab: _switchSearchTab,
            onSearch: _handleSearchSubmit,
          ),
        ),
      ],
    );
  }

  static const _rankingCategories = <({String name, String note, IconData icon})>[
    (name: '热门榜', note: '全站点歌次数排行', icon: Icons.local_fire_department),
    (name: '新歌榜', note: '近期新增歌曲排行', icon: Icons.auto_awesome),
    (name: '动画榜', note: '动画分类点歌排行', icon: Icons.tv),
    (name: 'VOCALOID榜', note: '术力口分类点歌排行', icon: Icons.smart_toy),
    (name: '华语榜', note: '华语歌曲点歌排行', icon: Icons.album),
    (name: '欧美榜', note: '欧美歌曲点歌排行', icon: Icons.public),
  ];

  Widget _buildRankingPage() {
    final rankingSongs = widget.searchService.featuredSongs.take(8).toList();
    final activeMeta = _rankingCategories.firstWhere(
      (r) => r.name == _activeRanking,
      orElse: () => _rankingCategories.first,
    );

    return Row(
      children: [
        SizedBox(
          width: 420,
          child: _RankingRail(
            categories: _rankingCategories,
            activeCategory: _activeRanking,
            onBack: widget.onExit,
            onSelected: (name) {
              setState(() => _activeRanking = name);
              widget.onAnnouncement('排行榜：$name');
            },
          ),
        ),
        const SizedBox(width: 22),
        Expanded(
          child: _SongResultPanel(
            title: activeMeta.name,
            subtitle: activeMeta.note,
            songs: rankingSongs,
            columns: 1,
            onAddSong: _addSong,
            onBumpSong: _bumpSong,
          ),
        ),
        const SizedBox(width: 22),
        SizedBox(
          width: 488,
          child: KaraokeInputPanel(
            activeTab: '排行',
            tabs: const ['排行'],
            placeholder: '在排行榜中搜索歌曲',
            controller: _searchQueryController.textController,
            searchFocusNode: _searchFocusNode,
            imeController: _imeController,
            onTab: _switchSearchTab,
            onSearch: _handleSearchSubmit,
          ),
        ),
      ],
    );
  }

  void _openArtist(ArtistSummary artist) {
    setState(() {
      _activeArtist = artist;
      _artistSongQuery = '';
      _mode = BrowseMode.artistDetail;
    });
    _syncSearchController();
    widget.onAnnouncement('打开：${artist.name}');
  }

  void _addSong(Song song) {
    widget.onAddSong(song);
    widget.onAnnouncement('已加入队列：${song.title}');
  }

  void _bumpSong(Song song) {
    widget.onBumpSong(song);
    widget.onAnnouncement('已顶到下一首：${song.title}');
  }

  void _switchSearchTab(String tab) {
    setState(() {
      _activeArtist = null;
      _mode = switch (tab) {
        '歌手' => BrowseMode.artists,
        '分类' => BrowseMode.categories,
        _ => BrowseMode.songs,
      };
    });
    _syncSearchController();
    widget.onAnnouncement('打开：$_modeTitle');
  }

  void _handleSearchChanged(String value) {
    setState(() {
      switch (_mode) {
        case BrowseMode.songs:
          _songQuery = value;
        case BrowseMode.artists:
          _artistQuery = value;
        case BrowseMode.artistDetail:
          _artistSongQuery = value;
        case BrowseMode.categories:
          _categoryQuery = value;
        case BrowseMode.externalLink:
        case BrowseMode.ranking:
          break;
      }
    });
  }

  void _handleSongScope(String scope) {
    setState(() => _songScope = scope);
    widget.onAnnouncement('搜索范围：$scope');
  }

  void _handleSearchControllerChanged() {
    if (!mounted) {
      return;
    }
    _handleSearchChanged(_searchQueryController.text);
  }

  void _handleSearchSubmit() {
    widget.onAnnouncement('搜索：${_searchQueryController.text}');
  }

  String get _modeTitle {
    return switch (_mode) {
      BrowseMode.songs => '歌名点歌',
      BrowseMode.artists => '歌手点歌',
      BrowseMode.artistDetail => _activeArtist?.name ?? '歌手详情',
      BrowseMode.categories => '分类点歌',
      BrowseMode.externalLink => '外链点歌',
      BrowseMode.ranking => '排行榜',
    };
  }

  String _currentQuery() {
    return switch (_mode) {
      BrowseMode.songs => _songQuery,
      BrowseMode.artists => _artistQuery,
      BrowseMode.artistDetail => _artistSongQuery,
      BrowseMode.categories => _categoryQuery,
      BrowseMode.externalLink => '',
      BrowseMode.ranking => '',
    };
  }

  List<Song> _scopedSongs() {
    var songs = widget.searchService.searchSongs(_songQuery);
    if (_songScope != '全部') {
      songs = songs.where((s) => s.category == _songScope).toList();
    }
    return songs;
  }

  List<String> get _songScopeOptions {
    final cats = widget.searchService.categories
        .where((c) => c.name != '热门')
        .map((c) => c.name)
        .toList();
    return ['全部', ...cats];
  }

  void _syncSearchController() {
    final value = _currentQuery();
    _searchQueryController.setText(value);
  }
}

class _SongResultPanel extends StatelessWidget {
  const _SongResultPanel({
    required this.title,
    required this.subtitle,
    required this.songs,
    required this.columns,
    required this.onAddSong,
    required this.onBumpSong,
  });

  final String title;
  final String subtitle;
  final List<Song> songs;
  final int columns;
  final ValueChanged<Song> onAddSong;
  final ValueChanged<Song> onBumpSong;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: _panelDecoration(),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Column(
          children: [
            _ResultHero(
              title: title,
              subtitle: subtitle,
              count: songs.length,
            ),
            Expanded(
              child: songs.isEmpty
                  ? const _EmptyState(text: '没有找到匹配歌曲')
                  : GridView.builder(
                      padding: const EdgeInsets.all(16),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        mainAxisExtent: 94,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                      ),
                      itemCount: songs.length,
                      itemBuilder: (context, index) {
                        return _SongResultCard(
                          song: songs[index],
                          index: index,
                          onAddSong: onAddSong,
                          onBumpSong: onBumpSong,
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultHero extends StatelessWidget {
  const _ResultHero({
    required this.title,
    required this.subtitle,
    required this.count,
  });

  final String title;
  final String subtitle;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 116,
      padding: const EdgeInsets.symmetric(horizontal: 30),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Color(0xff79335f),
            Color(0xff33466f),
          ],
        ),
        border: Border(bottom: BorderSide(color: KiraColors.line)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: KiraColors.cream,
                    fontSize: 42,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xdfffffff),
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '$count',
            style: const TextStyle(
              color: KiraColors.amber,
              fontSize: 50,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _SongResultCard extends StatelessWidget {
  const _SongResultCard({
    required this.song,
    required this.index,
    required this.onAddSong,
    required this.onBumpSong,
  });

  final Song song;
  final int index;
  final ValueChanged<Song> onAddSong;
  final ValueChanged<Song> onBumpSong;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: _cardDecoration(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            SizedBox(
              width: 52,
              child: Text(
                (index + 1).toString().padLeft(2, '0'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: KiraColors.amber,
                  fontSize: 23,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    song.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: KiraColors.cream,
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    '${song.artist.name} · ${song.category} · ${song.code ?? ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: KiraColors.muted,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              height: 56,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => onBumpSong(song),
                      borderRadius: BorderRadius.circular(8),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.arrow_upward, size: 14, color: KiraColors.muted),
                            SizedBox(width: 4),
                            Text(
                              '顶歌',
                              style: TextStyle(
                                color: KiraColors.muted,
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 120,
                    height: 56,
                    child: FilledButton(
                      onPressed: () => onAddSong(song),
                      style: FilledButton.styleFrom(
                        backgroundColor: KiraColors.red,
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text(
                        '点歌',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExternalLinkPanel extends StatelessWidget {
  const _ExternalLinkPanel({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: _panelDecoration(),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _BackButton(onPressed: onBack),
            const SizedBox(height: 28),
            const Text(
              '粘贴视频或音频链接自动解析',
              style: TextStyle(
                color: KiraColors.muted,
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: Container(
                    height: 70,
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    decoration: BoxDecoration(
                      color: const Color(0xfff3eee5),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0x1fffffff)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.link, color: KiraColors.red, size: 24),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'https://www.bilibili.com/video/BV... 或 YouTube / Niconico 等',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Color(0xff77746d),
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                SizedBox(
                  width: 136,
                  height: 70,
                  child: FilledButton.icon(
                    onPressed: null,
                    icon: const Icon(Icons.search, size: 22),
                    label: const Text(
                      '解析',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: KiraColors.red,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: KiraColors.red.withValues(alpha: 0.45),
                      disabledForegroundColor: Colors.white.withValues(alpha: 0.45),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              '基于 bilikara 引擎，支持 Bilibili、YouTube、Niconico 等平台。解析逻辑将在后续版本接入，届时支持 Windows 端粘贴与手机扫码输入。',
              style: TextStyle(
                color: KiraColors.muted,
                fontSize: 14,
                fontWeight: FontWeight.w800,
                height: 1.5,
              ),
            ),
            const Spacer(),
            const Center(
              child: Text(
                '外链解析功能即将上线\n敬请期待',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: KiraColors.muted,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  height: 1.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RankingRail extends StatelessWidget {
  const _RankingRail({
    required this.categories,
    required this.activeCategory,
    required this.onBack,
    required this.onSelected,
  });

  final List<({String name, String note, IconData icon})> categories;
  final String activeCategory;
  final VoidCallback onBack;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: _panelDecoration(),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _BackButton(onPressed: onBack),
            const SizedBox(height: 28),
            const Divider(color: KiraColors.line, height: 1),
            const SizedBox(height: 24),
            const Text(
              '榜单分类',
              style: TextStyle(
                color: KiraColors.muted,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 14),
            Expanded(
              child: ListView.separated(
                itemCount: categories.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final cat = categories[index];
                  final active = cat.name == activeCategory;
                  return SizedBox(
                    height: 96,
                    child: FilledButton(
                      onPressed: () => onSelected(cat.name),
                      style: FilledButton.styleFrom(
                        alignment: Alignment.centerLeft,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        backgroundColor: active
                            ? KiraColors.orange
                            : KiraColors.surface,
                        foregroundColor: KiraColors.cream,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                          side: BorderSide(
                            color: active
                                ? const Color(0x56ffcd9c)
                                : KiraColors.line,
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 54,
                            height: 54,
                            decoration: BoxDecoration(
                              color: const Color(0x1fffffff),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(cat.icon, color: KiraColors.cream),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  cat.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  cat.note,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: KiraColors.muted,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SongScopeRail extends StatelessWidget {
  const _SongScopeRail({
    required this.title,
    required this.options,
    required this.activeOption,
    required this.onBack,
    required this.onSelected,
  });

  final String title;
  final List<String> options;
  final String activeOption;
  final VoidCallback onBack;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: _panelDecoration(),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _BackButton(onPressed: onBack),
            const SizedBox(height: 28),
            const Divider(color: KiraColors.line, height: 1),
            const SizedBox(height: 24),
            Text(
              title,
              style: const TextStyle(
                color: KiraColors.muted,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 14),
            Expanded(
              child: ListView.separated(
                itemCount: options.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final option = options[index];
                  final active = option == activeOption;
                  return _RailOption(
                    label: option,
                    active: active,
                    onTap: () => onSelected(option),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OptionRail extends StatelessWidget {
  const _OptionRail({
    required this.title,
    required this.options,
    required this.activeOption,
    required this.onBack,
    required this.onSelected,
  });

  final String title;
  final List<String> options;
  final String activeOption;
  final VoidCallback onBack;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: _panelDecoration(),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _BackButton(onPressed: onBack),
            const SizedBox(height: 28),
            const Divider(color: KiraColors.line, height: 1),
            const SizedBox(height: 24),
            Text(
              title,
              style: const TextStyle(
                color: KiraColors.muted,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 14),
            Expanded(
              child: ListView.separated(
                itemCount: options.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final option = options[index];
                  final active = option == activeOption;
                  return _RailOption(
                    label: option,
                    active: active,
                    onTap: () => onSelected(option),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryRail extends StatelessWidget {
  const _CategoryRail({
    required this.categories,
    required this.activeCategory,
    required this.onBack,
    required this.onSelected,
  });

  final List<CategorySummary> categories;
  final String activeCategory;
  final VoidCallback onBack;
  final ValueChanged<CategorySummary> onSelected;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: _panelDecoration(),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _BackButton(onPressed: onBack),
            const SizedBox(height: 28),
            Expanded(
              child: ListView.separated(
                itemCount: categories.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final category = categories[index];
                  final active = category.name == activeCategory;
                  return _CategoryOption(
                    category: category,
                    active: active,
                    onTap: () => onSelected(category),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RailOption extends StatelessWidget {
  const _RailOption({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 64,
      child: FilledButton(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          backgroundColor: active ? const Color(0xff1d2e4b) : Colors.transparent,
          foregroundColor: active ? const Color(0xff77a7ff) : KiraColors.cream,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(
              color: active ? const Color(0xff4777c6) : Colors.transparent,
            ),
          ),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _CategoryOption extends StatelessWidget {
  const _CategoryOption({
    required this.category,
    required this.active,
    required this.onTap,
  });

  final CategorySummary category;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 92,
      child: FilledButton(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          backgroundColor: active ? KiraColors.surface3 : KiraColors.surface,
          foregroundColor: KiraColors.cream,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(
              color: active ? KiraColors.lineStrong : KiraColors.line,
            ),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: const Color(0x1fffffff),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(_categoryIcon(category.name), color: KiraColors.cream),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    category.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    category.note,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: KiraColors.muted,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ArtistResultPanel extends StatelessWidget {
  const _ArtistResultPanel({
    required this.artists,
    required this.songCountForArtist,
    required this.onArtist,
  });

  final List<ArtistSummary> artists;
  final int Function(ArtistSummary artist) songCountForArtist;
  final ValueChanged<ArtistSummary> onArtist;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: _panelDecoration(),
      child: artists.isEmpty
          ? const _EmptyState(text: '没有匹配歌手')
          : GridView.builder(
              padding: const EdgeInsets.all(18),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisExtent: 140,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
              ),
              itemCount: artists.length,
              itemBuilder: (context, index) {
                final artist = artists[index];
                return _ArtistCard(
                  artist: artist,
                  songCount: songCountForArtist(artist),
                  onTap: () => onArtist(artist),
                );
              },
            ),
    );
  }
}

class _ArtistCard extends StatelessWidget {
  const _ArtistCard({
    required this.artist,
    required this.songCount,
    required this.onTap,
  });

  final ArtistSummary artist;
  final int songCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Ink(
          decoration: _cardDecoration(),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                _AvatarLetter(text: artist.name.characters.first, size: 72),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        artist.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: KiraColors.cream,
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        '${artist.type} · ${artist.note}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: KiraColors.muted,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 10),
                      _CountPill(text: '$songCount 首歌曲'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ArtistDetailRail extends StatelessWidget {
  const _ArtistDetailRail({
    required this.artist,
    required this.songCount,
    required this.searchController,
    required this.onBack,
    required this.onSearchChanged,
  });

  final ArtistSummary artist;
  final int songCount;
  final TextEditingController searchController;
  final VoidCallback onBack;
  final ValueChanged<String> onSearchChanged;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: _panelDecoration(),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SizedBox(width: 132, child: _BackButton(onPressed: onBack)),
                const SizedBox(width: 12),
                Expanded(
                  child: _CompactSearchField(
                    controller: searchController,
                    hintText: '在歌手内搜索',
                    onChanged: onSearchChanged,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            _AvatarLetter(
              text: artist.name.characters.first,
              size: 376,
              fontSize: 104,
            ),
            const SizedBox(height: 24),
            Text(
              artist.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: KiraColors.cream,
                fontSize: 37,
                height: 1.1,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              '${artist.group} · ${artist.note}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: KiraColors.muted,
                fontSize: 18,
                height: 1.35,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            Container(
              height: 64,
              width: double.infinity,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0x1af2b84b),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0x45f2b84b)),
              ),
              child: Text(
                '共 $songCount 首歌曲',
                style: const TextStyle(
                  color: KiraColors.amber,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CompactSearchField extends StatelessWidget {
  const _CompactSearchField({
    required this.controller,
    required this.hintText,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: const TextStyle(
            color: Color(0x99ffffff),
            fontWeight: FontWeight.w700,
          ),
          prefixIcon: const Icon(Icons.search, color: Color(0xccffffff)),
          filled: true,
          fillColor: const Color(0x18ffffff),
          contentPadding: EdgeInsets.zero,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: KiraColors.line),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: KiraColors.line),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: KiraColors.lineStrong),
          ),
        ),
        style: const TextStyle(
          color: KiraColors.cream,
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _BackButton extends StatelessWidget {
  const _BackButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: FilledButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.chevron_left, size: 28),
        label: const Text(
          '返回',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
        style: FilledButton.styleFrom(
          backgroundColor: KiraColors.surface2,
          foregroundColor: KiraColors.cream,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: const BorderSide(color: KiraColors.line),
          ),
        ),
      ),
    );
  }
}

class _AvatarLetter extends StatelessWidget {
  const _AvatarLetter({
    required this.text,
    required this.size,
    this.fontSize,
  });

  final String text;
  final double size;
  final double? fontSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xff3f6fea),
            Color(0xffd94e91),
          ],
        ),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0x29ffffff)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: Colors.white,
          fontSize: fontSize ?? size * 0.42,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _CountPill extends StatelessWidget {
  const _CountPill({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: const Color(0x1af2b84b),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: KiraColors.amber,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        text,
        style: const TextStyle(
          color: KiraColors.muted,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

IconData _categoryIcon(String name) {
  return switch (name) {
    '热门' => Icons.local_fire_department,
    '动画' => Icons.auto_awesome,
    'VOCALOID' => Icons.smart_toy,
    '东方' => Icons.nights_stay,
    '经典' => Icons.star,
    '角色歌' => Icons.person,
    _ => Icons.library_music,
  };
}

BoxDecoration _panelDecoration() {
  return BoxDecoration(
    color: KiraColors.surface,
    borderRadius: BorderRadius.circular(10),
    border: Border.all(color: KiraColors.line),
  );
}

BoxDecoration _cardDecoration() {
  return BoxDecoration(
    color: KiraColors.surface2,
    borderRadius: BorderRadius.circular(10),
    border: Border.all(color: KiraColors.line),
  );
}
