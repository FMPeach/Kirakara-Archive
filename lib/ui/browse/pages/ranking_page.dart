part of '../../screens/browse_screen.dart';

extension _RankingPage on _BrowseScreenState {
  static const _rankingCategories =
      <({String name, String note, IconData icon})>[
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
          width: KiraLayout.browseRailWidth,
          child: _RankingRail(
            categories: _rankingCategories,
            activeCategory: _activeRanking,
            onBack: widget.onExit,
            onSelected: (name) {
              _update(() => _activeRanking = name);
            },
          ),
        ),
        const SizedBox(width: KiraLayout.sectionGap),
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
        const SizedBox(width: KiraLayout.sectionGap),
        SizedBox(
          width: KiraLayout.inputPanelWidth,
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
}
