part of '../../screens/controller_screen.dart';

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.customAnnouncement,
    required this.playbackService,
    required this.isLoading,
    required this.isBuffering,
    required this.showSearch,
    required this.controllerFullscreen,
    required this.isCasting,
    required this.onSearchTap,
    required this.onQr,
    required this.onSettings,
    required this.onFullscreen,
    required this.onCast,
  });

  final String customAnnouncement;
  final PlaybackService playbackService;
  final bool isLoading;
  final bool isBuffering;
  final bool showSearch;
  final bool controllerFullscreen;
  final bool isCasting;
  final VoidCallback onSearchTap;
  final VoidCallback onQr;
  final VoidCallback onSettings;
  final VoidCallback onFullscreen;
  final VoidCallback onCast;

  @override
  Widget build(BuildContext context) {
    final state = playbackService.state;
    final tickerText = _tickerText(
      customAnnouncement: customAnnouncement,
      current: state.currentSong,
      next: state.upNext?.song,
      mode: state.mode,
      isLoading: isLoading,
      isBuffering: isBuffering,
    );
    final brandBlock = SizedBox(
      width: 325,
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: KiraColors.cream,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.graphic_eq,
              color: KiraColors.red,
              size: 30,
            ),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: Transform.translate(
                offset: const Offset(0, 4),
                child: Image.asset(
                  'assets/branding/wordmark.png',
                  height: 40,
                  fit: BoxFit.contain,
                  alignment: Alignment.centerLeft,
                  filterQuality: FilterQuality.high,
                  semanticLabel: 'Kira Karaoke',
                ),
              ),
            ),
          ),
        ],
      ),
    );
    final tickerBlock = Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 19),
      decoration: BoxDecoration(
        color: const Color(0xff111216),
        border: Border.all(color: KiraColors.line),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const _TickerTag(text: '报幕'),
          const SizedBox(width: 15),
          Expanded(
            child: _MarqueeText(
              text: tickerText,
              style: const TextStyle(
                color: KiraColors.cream,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );

    Widget buildActions({required bool includeSearch}) {
      return Row(
        mainAxisSize: includeSearch ? MainAxisSize.max : MainAxisSize.min,
        children: [
          if (includeSearch) ...[
            Expanded(
              child: _TopSearchEntry(onPressed: onSearchTap),
            ),
            const SizedBox(width: 15),
          ],
          _TopIconButton(
            icon: Icons.qr_code,
            tooltip: '手机点歌',
            onPressed: onQr,
          ),
          const SizedBox(width: 15),
          _TopIconButton(
            icon: Icons.settings,
            tooltip: '设置',
            onPressed: onSettings,
          ),
          const SizedBox(width: 15),
          _TopIconButton(
            icon:
                controllerFullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
            tooltip: controllerFullscreen ? '退出全屏' : '全屏',
            onPressed: onFullscreen,
          ),
          const SizedBox(width: 15),
          _TopTextButton(
            icon: Icons.cast,
            width: 115,
            label: isCasting ? '投屏中' : '投屏',
            active: isCasting,
            onPressed: onCast,
          ),
        ],
      );
    }

    return Container(
      height: 95,
      padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 18),
      decoration: const BoxDecoration(
        color: Color(0xf5121317),
        border: Border(bottom: BorderSide(color: KiraColors.line)),
      ),
      child: Row(
        children: showSearch
            ? [
                Expanded(
                  flex: 2,
                  child: Row(
                    children: [
                      brandBlock,
                      const SizedBox(width: 22),
                      Expanded(child: tickerBlock),
                    ],
                  ),
                ),
                const SizedBox(width: 22),
                Expanded(
                  flex: 1,
                  child: buildActions(includeSearch: true),
                ),
              ]
            : [
                brandBlock,
                const SizedBox(width: 22),
                Expanded(child: tickerBlock),
                const SizedBox(width: 22),
                buildActions(includeSearch: false),
              ],
      ),
    );
  }

  static String _tickerText({
    required String customAnnouncement,
    required Song? current,
    required Song? next,
    required PlaybackMode mode,
    required bool isLoading,
    required bool isBuffering,
  }) {
    final custom = customAnnouncement.trim();
    final parts = <String>[
      if (custom.isNotEmpty) custom,
      '当前播放：${_songLabel(current, fallback: '等待点歌')}',
      if (isLoading)
        '正在加载'
      else if (isBuffering)
        '正在缓冲'
      else if (current == null || mode == PlaybackMode.stopped)
        '已停止'
      else if (mode == PlaybackMode.paused)
        '暂停中',
      next == null ? '下一首：暂无，快去点一首吧' : '下一首：${_songLabel(next)}',
    ];
    return parts.join('  ·  ');
  }

  static String _songLabel(Song? song, {String fallback = '暂无'}) {
    if (song == null) return fallback;
    return '${song.title} - ${song.artist?.name ?? '未知歌手'}';
  }
}

class _MarqueeText extends StatefulWidget {
  const _MarqueeText({
    required this.text,
    required this.style,
  });

  final String text;
  final TextStyle style;

  @override
  State<_MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<_MarqueeText>
    with WidgetsBindingObserver {
  // A continuous Flutter animation keeps the entire Windows surface in the
  // VSync frame pump even when only this text moves. Show long announcements
  // as instant pages instead: one frame per page, then a completely idle UI.
  static const double _overflowSafetyMargin = 12;
  static const Duration _pageInterval = Duration(seconds: 5);

  Timer? _pageTimer;
  int _pageIndex = 0;
  bool _appVisible = true;
  List<String> _pages = const [];
  String? _cachedText;
  TextStyle? _cachedStyle;
  TextScaler? _cachedTextScaler;
  TextDirection? _cachedTextDirection;
  Locale? _cachedLocale;
  double? _cachedAvailableWidth;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _appVisible = _isVisible(WidgetsBinding.instance.lifecycleState);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final visible = _isVisible(state);
    if (_appVisible == visible) return;
    _appVisible = visible;
    if (visible) {
      _scheduleNextPage();
    } else {
      _pageTimer?.cancel();
      _pageTimer = null;
    }
  }

  @override
  void didUpdateWidget(covariant _MarqueeText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text || oldWidget.style != widget.style) {
      _invalidatePages();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pageTimer?.cancel();
    super.dispose();
  }

  static bool _isVisible(AppLifecycleState? state) {
    return state == null ||
        state == AppLifecycleState.resumed ||
        state == AppLifecycleState.inactive;
  }

  void _invalidatePages() {
    _pageTimer?.cancel();
    _pageTimer = null;
    _pageIndex = 0;
    _pages = const [];
    _cachedText = null;
    _cachedStyle = null;
    _cachedTextScaler = null;
    _cachedTextDirection = null;
    _cachedLocale = null;
    _cachedAvailableWidth = null;
  }

  void _scheduleNextPage() {
    if (!_appVisible || _pages.length <= 1 || _pageTimer != null) return;
    _pageTimer = Timer(_pageInterval, () {
      _pageTimer = null;
      if (!mounted || !_appVisible || _pages.length <= 1) return;
      setState(() {
        _pageIndex = (_pageIndex + 1) % _pages.length;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      key: const ValueKey('marquee-viewport'),
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;
        final effectiveStyle = DefaultTextStyle.of(context).style.merge(
              widget.style,
            );
        final textScaler = MediaQuery.textScalerOf(context);
        final textDirection = Directionality.of(context);
        final locale = Localizations.maybeLocaleOf(context);
        final pages = _pagesFor(
          text: widget.text,
          style: effectiveStyle,
          textScaler: textScaler,
          textDirection: textDirection,
          locale: locale,
          availableWidth: availableWidth,
        );
        _pages = pages;
        if (_pageIndex >= pages.length) _pageIndex = 0;
        _scheduleNextPage();

        final paged = pages.length > 1;
        return RepaintBoundary(
          child: Semantics(
            label: widget.text,
            excludeSemantics: true,
            child: Text(
              key: ValueKey(
                paged ? 'marquee-page-run' : 'marquee-static-run',
              ),
              pages[_pageIndex],
              maxLines: 1,
              overflow: TextOverflow.clip,
              softWrap: false,
              style: widget.style,
            ),
          ),
        );
      },
    );
  }

  List<String> _pagesFor({
    required String text,
    required TextStyle style,
    required TextScaler textScaler,
    required TextDirection textDirection,
    required Locale? locale,
    required double availableWidth,
  }) {
    if (_cachedText == text &&
        _cachedStyle == style &&
        _cachedTextScaler == textScaler &&
        _cachedTextDirection == textDirection &&
        _cachedLocale == locale &&
        _cachedAvailableWidth == availableWidth &&
        _pages.isNotEmpty) {
      return _pages;
    }

    _pageTimer?.cancel();
    _pageTimer = null;
    _pageIndex = 0;
    _cachedText = text;
    _cachedStyle = style;
    _cachedTextScaler = textScaler;
    _cachedTextDirection = textDirection;
    _cachedLocale = locale;
    _cachedAvailableWidth = availableWidth;

    if (!availableWidth.isFinite || availableWidth <= 0 || text.isEmpty) {
      return <String>[text];
    }
    final maxWidth = availableWidth - _overflowSafetyMargin;
    if (_fits(
      text,
      maxWidth: maxWidth,
      style: style,
      textScaler: textScaler,
      textDirection: textDirection,
      locale: locale,
    )) {
      return <String>[text];
    }

    final characters = text.runes.map(String.fromCharCode).toList();
    final pages = <String>[];
    var start = 0;
    while (start < characters.length) {
      while (start < characters.length && characters[start].trim().isEmpty) {
        start++;
      }
      if (start >= characters.length) break;

      var low = 1;
      var high = characters.length - start;
      var best = 1;
      while (low <= high) {
        final middle = (low + high) ~/ 2;
        final hasMore = start + middle < characters.length;
        final candidate =
            '${characters.sublist(start, start + middle).join()}${hasMore ? '…' : ''}';
        if (_fits(
          candidate,
          maxWidth: maxWidth,
          style: style,
          textScaler: textScaler,
          textDirection: textDirection,
          locale: locale,
        )) {
          best = middle;
          low = middle + 1;
        } else {
          high = middle - 1;
        }
      }

      final end = start + best;
      final hasMore = end < characters.length;
      final page = characters.sublist(start, end).join().trim();
      pages.add('$page${hasMore ? '…' : ''}');
      start = end;
    }
    return pages.isEmpty ? <String>[text] : pages;
  }

  static bool _fits(
    String text, {
    required double maxWidth,
    required TextStyle style,
    required TextScaler textScaler,
    required TextDirection textDirection,
    required Locale? locale,
  }) {
    if (maxWidth <= 0) return false;
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      maxLines: 1,
      textDirection: textDirection,
      textScaler: textScaler,
      locale: locale,
    )..layout();
    final fits = painter.width <= maxWidth;
    painter.dispose();
    return fits;
  }
}

class _TickerTag extends StatelessWidget {
  const _TickerTag({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 35,
      padding: const EdgeInsets.symmetric(horizontal: 13),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0x1af2b84b),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0x2ef2b84b)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: KiraColors.amber,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _TopSearchEntry extends StatelessWidget {
  const _TopSearchEntry({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 60,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          backgroundColor: KiraColors.surface2,
          foregroundColor: KiraColors.muted,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: const BorderSide(color: KiraColors.line),
          ),
        ),
        child: const Row(
          children: [
            Icon(
              Icons.search,
              size: 30,
            ),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                '搜索歌名、歌手、编号',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 19,
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

class _TopIconButton extends StatelessWidget {
  const _TopIconButton({
    required this.icon,
    required this.onPressed,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 65,
      height: 60,
      child: IconButton.filled(
        onPressed: onPressed,
        tooltip: tooltip,
        icon: Icon(icon, size: 30),
        style: IconButton.styleFrom(
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

class _TopTextButton extends StatelessWidget {
  const _TopTextButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.width = 98,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final double width;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: 60,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          backgroundColor:
              active ? const Color(0x1fdd3e38) : KiraColors.surface2,
          foregroundColor: active ? const Color(0xffff827d) : KiraColors.cream,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(
              color: active ? const Color(0x6bdd3e38) : KiraColors.line,
            ),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 30),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 19,
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
