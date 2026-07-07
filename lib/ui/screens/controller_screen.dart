import 'package:flutter/material.dart';

import '../../domain/playback_state.dart';
import '../../domain/song.dart';
import '../../engine/stage_renderer.dart';
import '../../services/cast_service.dart';
import '../../services/display_manager.dart';
import '../../services/kirakara_show_service.dart';
import '../../services/lan_server.dart';
import '../../services/native_window_service.dart';
import '../../services/playback_service.dart';
import '../../services/queue_service.dart';
import '../../services/search_service.dart';
import '../theme/kirakara_theme.dart';
import '../widgets/kira_design_canvas.dart';
import '../widgets/ktv_button.dart';
import '../widgets/mock_qr.dart';
import 'browse_screen.dart';
import 'stage_screen.dart';

class ControllerScreen extends StatefulWidget {
  const ControllerScreen({
    super.key,
    required this.searchService,
    required this.queueService,
    required this.playbackService,
    required this.displayManager,
    required this.kirakaraShowService,
    required this.castService,
    required this.lanServer,
    required this.stageRenderer,
  });

  final SearchService searchService;
  final QueueService queueService;
  final PlaybackService playbackService;
  final DisplayManager displayManager;
  final KirakaraShowService kirakaraShowService;
  final CastService castService;
  final LanServer lanServer;
  final StageRenderer stageRenderer;

  @override
  State<ControllerScreen> createState() => _ControllerScreenState();
}

class _ControllerScreenState extends State<ControllerScreen> {
  final NativeWindowService _nativeWindowService = const NativeWindowService();
  BrowseMode? _browseMode;
  String _browseInitialQuery = '';
  int _browseSerial = 0;
  String _announcement = '欢迎使用 Kira Karaoke，本机队列已就绪';
  bool _controllerFullscreen = false;

  @override
  void initState() {
    super.initState();
    _startLanServer();
    _loadControllerFullscreenState();
  }

  Future<void> _loadControllerFullscreenState() async {
    final fullscreen = await _nativeWindowService.isControllerFullscreen();
    if (!mounted) return;
    setState(() => _controllerFullscreen = fullscreen);
  }

  Future<void> _startLanServer() async {
    try {
      await widget.lanServer.start();
      if (!mounted) {
        return;
      }
      setState(() {
        _announcement = '手机点歌服务已启动：${widget.lanServer.localUri}';
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _announcement = '手机点歌服务未启动，可在设定中重试';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: KiraDesignCanvas(
        child: AnimatedBuilder(
          animation: Listenable.merge([
            widget.playbackService,
            widget.queueService,
            widget.displayManager,
            widget.castService,
          ]),
          builder: (context, _) {
            return DecoratedBox(
              decoration: const BoxDecoration(
                color: KiraColors.bg,
                boxShadow: [
                  BoxShadow(
                    color: Color(0xaa000000),
                    blurRadius: 48,
                  ),
                ],
              ),
              child: Column(
                children: [
                  _TopBar(
                    announcement: _announcement,
                    playbackService: widget.playbackService,
                    showSearch: _browseMode == null,
                    controllerFullscreen: _controllerFullscreen,
                    onSearchTap: () => _runSearch(''),
                    onQr: _showQrDialog,
                    onSettings: _showSettingsDialog,
                    onFullscreen: _toggleControllerFullscreen,
                    onCast: _showCastDialog,
                  ),
                  Expanded(
                    child: _browseMode == null
                        ? Padding(
                            padding: const EdgeInsets.fromLTRB(30, 28, 30, 22),
                            child: Row(
                              children: [
                                Expanded(
                                  flex: 2,
                                  child: _LeftPane(
                                    playbackService: widget.playbackService,
                                    stageRenderer: widget.stageRenderer,
                                  ),
                                ),
                                const SizedBox(width: 22),
                                Expanded(
                                  flex: 1,
                                  child: _RightPane(
                                    onPanel: _showPanel,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : BrowseScreen(
                            key: ValueKey(_browseSerial),
                            searchService: widget.searchService,
                            initialMode: _browseMode!,
                            initialQuery: _browseInitialQuery,
                            onExit: _closeBrowsePage,
                            onAddSong: _addSong,
                            onBumpSong: _bumpSong,
                            onAnnouncement: _setAnnouncement,
                          ),
                  ),
                  _BottomBar(
                    playbackService: widget.playbackService,
                    queueService: widget.queueService,
                    castService: widget.castService,
                    onQueue: _showQueueDialog,
                    onAfterQueueChanged: () {
                      widget.playbackService.refreshUpNext();
                    },
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _runSearch(String query) async {
    setState(() {
      _browseMode = BrowseMode.songs;
      _browseInitialQuery = query.trim();
      _browseSerial++;
      _announcement =
          _browseInitialQuery.isEmpty ? '打开：歌名点歌' : '搜索：$_browseInitialQuery';
    });
  }

  void _addSong(Song song) {
    final item = widget.queueService.addSong(song);
    if (widget.playbackService.state.currentItem == null) {
      widget.playbackService.setCurrentFromQueue(item, startPlaying: true);
    } else {
      widget.playbackService.refreshUpNext();
    }
    setState(() {
      _announcement = '已加入队列：${song.title}';
    });
  }

  void _bumpSong(Song song) {
    final item = widget.queueService.bumpToNext(song);
    if (widget.playbackService.state.currentItem == null) {
      widget.playbackService.setCurrentFromQueue(item, startPlaying: true);
    } else {
      widget.playbackService.refreshUpNext();
    }
    setState(() {
      _announcement = '已顶到下一首：${song.title}';
    });
  }

  void _showPanel(String title) {
    final mode = switch (title) {
      '歌名点歌' => BrowseMode.songs,
      '歌手点歌' => BrowseMode.artists,
      '分类点歌' => BrowseMode.categories,
      '外链点歌' => BrowseMode.externalLink,
      '排行榜' => BrowseMode.ranking,
      _ => null,
    };

    if (mode == null) {
      _showDialogAboveNativePreview<void>(
        builder: (context) {
          return _KiraDialog(
            title: title,
            width: 500,
            child: Text(
              '$title 后续会接入对应的列表、排序和加入队列流程。',
              style: const TextStyle(
                color: KiraColors.muted,
                height: 1.6,
                fontWeight: FontWeight.w700,
              ),
            ),
          );
        },
      );
      return;
    }

    setState(() {
      _browseMode = mode;
      _browseInitialQuery = '';
      _browseSerial++;
      _announcement = '打开：$title';
    });
  }

  void _closeBrowsePage() {
    setState(() {
      _browseMode = null;
      _browseInitialQuery = '';
      _announcement = '已返回点歌首页';
    });
  }

  void _setAnnouncement(String value) {
    setState(() {
      _announcement = value;
    });
  }

  void _showQueueDialog() {
    _showDialogAboveNativePreview<void>(
      builder: (context) {
        return AnimatedBuilder(
          animation:
              Listenable.merge([widget.queueService, widget.playbackService]),
          builder: (context, _) {
            final currentItem = widget.playbackService.state.currentItem;
            final queueItems = widget.queueService.items;
            return _KiraDialog(
              title: '点歌列表',
              width: 680,
              child: SizedBox(
                height: 420,
                child: Column(
                  children: [
                    // ── 正在播放 ──
                    if (currentItem != null) ...[
                      _QueueItemRow(
                        index: 0,
                        song: currentItem.song,
                        subtitle: '${currentItem.song.artist?.name ?? '未知'} · 正在播放',
                        isCurrent: true,
                        onBump: null,
                        onDelete: null,
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          children: [
                            Text(
                              '下一首',
                              style: TextStyle(
                                color: KiraColors.muted,
                                fontSize: 13,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            SizedBox(width: 10),
                            Expanded(
                              child: Divider(height: 1, color: KiraColors.line),
                            ),
                          ],
                        ),
                      ),
                    ],
                    // ── 队列 ──
                    Expanded(
                      child: queueItems.isEmpty
                          ? const Center(
                              child: Text(
                                '队列为空，去点一首歌吧',
                                style: TextStyle(
                                  color: KiraColors.muted,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            )
                          : ListView.builder(
                              itemCount: queueItems.length,
                              itemBuilder: (context, index) {
                                final item = queueItems[index];
                                return _QueueItemRow(
                                  index: index + 1,
                                  song: item.song,
                                  subtitle:
                                      '${item.song.artist?.name ?? '未知'} · ${item.song.category}',
                                  isCurrent: false,
                                  onBump: () {
                                    widget.queueService.bumpItemToNext(item.id);
                                    widget.playbackService.refreshUpNext();
                                  },
                                  onDelete: () {
                                    widget.queueService.remove(item.id);
                                    widget.playbackService.refreshUpNext();
                                  },
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showQrDialog() {
    _showDialogAboveNativePreview<void>(
      builder: (context) {
        return _KiraDialog(
          title: '手机点歌',
          width: 430,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const MockQrCode(size: 210),
              const SizedBox(height: 18),
              Text(
                widget.lanServer.localUri?.toString() ?? 'http://本机局域网地址:7391',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: KiraColors.amber,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                '第一版为 LAN-only mock handler。手机扫码后只访问本机 HTTP 服务，不经过公网服务器。',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: KiraColors.muted,
                  height: 1.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _toggleControllerFullscreen() async {
    final next = !_controllerFullscreen;
    final ok = await _nativeWindowService.setControllerFullscreen(next);
    if (!mounted) return;
    setState(() => _controllerFullscreen = ok ? next : _controllerFullscreen);
  }

  void _showCastDialog() {
    _showDialogAboveNativePreview<void>(
      builder: (context) {
        return AnimatedBuilder(
          animation:
              Listenable.merge([widget.displayManager, widget.castService]),
          builder: (context, _) {
            final isDualStage =
                widget.displayManager.mode == DisplayMode.dualScreen;
            final isPreviewStage =
                widget.displayManager.mode == DisplayMode.previewWindow;
            final stageDisplay = widget.displayManager.stageDisplay;
            return _KiraDialog(
              title: '投屏与舞台输出',
              width: 620,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _StatusLine(
                    icon: Icons.monitor,
                    label: '舞台输出',
                    value: _displayModeLabel(widget.displayManager.mode),
                  ),
                  _StatusLine(
                    icon: Icons.desktop_windows,
                    label: '显示器',
                    value: stageDisplay == null
                        ? '未检测到第二屏'
                        : '${stageDisplay.name} · ${stageDisplay.sizeLabel}',
                  ),
                  _StatusLine(
                    icon: Icons.cast,
                    label: '投屏',
                    value: widget.castService.isCasting
                        ? '正在输出 Stage：${widget.castService.targetName}'
                        : '未投屏',
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: stageDisplay == null && !isDualStage
                              ? null
                              : () => isDualStage
                                  ? _closeStageOutput()
                                  : _openPhysicalStageOutput(),
                          icon: Icon(
                            isDualStage
                                ? Icons.close_fullscreen
                                : Icons.connected_tv,
                          ),
                          label: Text(
                            isDualStage ? '关闭第二屏' : '打开第二屏',
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () => isPreviewStage
                              ? _closeStageOutput()
                              : _openDebugStageWindow(),
                          icon: const Icon(Icons.screenshot_monitor),
                          label: Text(isPreviewStage ? '关闭调试窗' : '调试窗口'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _refreshDisplays,
                          icon: const Icon(Icons.refresh),
                          label: const Text('刷新显示器'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () {
                            widget.castService.isCasting
                                ? widget.castService.stopCast()
                                : widget.castService.startMockCast();
                          },
                          icon: Icon(
                            widget.castService.isCasting
                                ? Icons.cast_connected
                                : Icons.cast,
                          ),
                          label: Text(
                            widget.castService.isCasting ? '停止投屏' : 'Mock 投屏',
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _openPhysicalStageOutput() async {
    final display = widget.displayManager.stageDisplay;
    if (display == null) return;
    widget.kirakaraShowService.setStageWindowRect(
      x: display.left,
      y: display.top,
      width: display.width,
      height: display.height,
    );
    await widget.displayManager.openStageWindow(preview: false);
    widget.kirakaraShowService.setStageWindowVisible(true);
  }

  Future<void> _openDebugStageWindow() async {
    final display = widget.displayManager.controllerDisplay;
    const width = 960;
    const height = 540;
    widget.kirakaraShowService.setStageWindowRect(
      x: display.left + 80,
      y: display.top + 80,
      width: width,
      height: height,
    );
    await widget.displayManager.openStageWindow(preview: true);
    widget.kirakaraShowService.setStageWindowVisible(true);
  }

  Future<void> _closeStageOutput() async {
    await widget.displayManager.closeStageWindow();
    widget.kirakaraShowService.setStageWindowVisible(false);
  }

  Future<void> _refreshDisplays() async {
    await widget.displayManager.detectDisplays();
    if (widget.displayManager.stageDisplay == null &&
        widget.displayManager.mode == DisplayMode.singleScreen) {
      widget.kirakaraShowService.setStageWindowVisible(false);
    }
  }

  void _showSettingsDialog() {
    _showDialogAboveNativePreview<void>(
      builder: (context) {
        // TODO: add Settings controls for custom announcement text and the
        // video/stage QR overlay switch. Keep them hidden until the behavior is
        // wired end-to-end.
        return _KiraDialog(
          title: '设定',
          width: 560,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _StatusLine(
                icon: Icons.router,
                label: '手机点歌',
                value: widget.lanServer.isRunning
                    ? '已启动：${widget.lanServer.localUri}'
                    : '未启动',
              ),
              const _StatusLine(
                icon: Icons.volume_up,
                label: '音频输出',
                value: '默认设备',
              ),
              const _StatusLine(
                icon: Icons.keyboard,
                label: '输入方式',
                value: '触控输入法 / 系统键盘',
              ),
              const _StatusLine(
                icon: Icons.storage,
                label: '本地缓存',
                value: '媒体、封面与 KRL 缓存目录',
              ),
              const SizedBox(height: 14),
              const Text(
                '这里预留通用设置：LAN 服务端口、音频设备、输入法、曲库缓存、系统行为等。投屏和舞台输出放到右上角“投屏”里。',
                style: TextStyle(
                  color: KiraColors.muted,
                  height: 1.55,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<T?> _showDialogAboveNativePreview<T>({
    required WidgetBuilder builder,
  }) {
    final showService = widget.kirakaraShowService;
    showService.setControllerPreviewSuppressed(true);
    return showDialog<T>(
      context: context,
      builder: builder,
    ).whenComplete(() {
      showService.setControllerPreviewSuppressed(false);
    });
  }

  static String _displayModeLabel(DisplayMode mode) {
    return switch (mode) {
      DisplayMode.singleScreen => '单屏控制台',
      DisplayMode.dualScreen => '双屏异显',
      DisplayMode.previewWindow => '调试预览窗口',
    };
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.announcement,
    required this.playbackService,
    required this.showSearch,
    required this.controllerFullscreen,
    required this.onSearchTap,
    required this.onQr,
    required this.onSettings,
    required this.onFullscreen,
    required this.onCast,
  });

  final String announcement;
  final PlaybackService playbackService;
  final bool showSearch;
  final bool controllerFullscreen;
  final VoidCallback onSearchTap;
  final VoidCallback onQr;
  final VoidCallback onSettings;
  final VoidCallback onFullscreen;
  final VoidCallback onCast;

  @override
  Widget build(BuildContext context) {
    final state = playbackService.state;
    final tickerText = _tickerText(
      announcement: announcement,
      current: state.currentSong,
      next: state.upNext?.song,
      isPaused: state.currentSong != null && !state.isPlaying,
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
          const Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Kira Karaoke',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 25,
                    height: 1,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  '家庭 KTV / 实时歌词系统',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: KiraColors.muted,
                    fontSize: 15,
                    height: 1,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
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
            tooltip: '设定',
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
            label: '投屏',
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
    required String announcement,
    required Song? current,
    required Song? next,
    required bool isPaused,
  }) {
    final parts = <String>[
      announcement.trim().isEmpty ? '欢迎使用 Kira Karaoke' : announcement.trim(),
      '当前播放：${_songLabel(current, fallback: '等待点歌')}',
      if (isPaused) '暂停中',
      next == null ? '下一首：暂无，快去点一首吧' : '下一首：${_songLabel(next)}',
    ];
    return parts.join('  ·  ');
  }

  static String _songLabel(Song? song, {String fallback = '暂无'}) {
    if (song == null) return fallback;
    return '${song.artist?.name ?? '未知'} - ${song.title}';
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
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);
  }

  @override
  void didUpdateWidget(covariant _MarqueeText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text || oldWidget.style != widget.style) {
      _controller
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final textWidth = _measureText(context, widget.text, widget.style);
        final availableWidth = constraints.maxWidth;
        if (!textWidth.isFinite ||
            !availableWidth.isFinite ||
            textWidth <= availableWidth) {
          _controller.stop();
          return Text(
            widget.text,
            maxLines: 1,
            overflow: TextOverflow.visible,
            softWrap: false,
            style: widget.style,
          );
        }

        const gap = 80.0;
        final distance = textWidth + gap;
        final duration = Duration(
          milliseconds: (distance / 68 * 1000).round().clamp(5000, 30000),
        );
        if (!_controller.isAnimating || _controller.duration != duration) {
          _controller
            ..duration = duration
            ..repeat();
        }

        return ClipRect(
          child: SizedBox.expand(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                final offset = -distance * _controller.value;
                return Align(
                  alignment: Alignment.centerLeft,
                  child: OverflowBox(
                    alignment: Alignment.centerLeft,
                    minWidth: 0,
                    maxWidth: double.infinity,
                    child: Transform.translate(
                      offset: Offset(offset, 0),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _MarqueeTextRun(
                            text: widget.text,
                            style: widget.style,
                          ),
                          const SizedBox(width: gap),
                          _MarqueeTextRun(
                            text: widget.text,
                            style: widget.style,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  static double _measureText(
    BuildContext context,
    String text,
    TextStyle style,
  ) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      maxLines: 1,
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    return painter.width;
  }
}

class _MarqueeTextRun extends StatelessWidget {
  const _MarqueeTextRun({
    required this.text,
    required this.style,
  });

  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.visible,
      softWrap: false,
      style: style,
    );
  }
}

class _LeftPane extends StatelessWidget {
  const _LeftPane({
    required this.playbackService,
    required this.stageRenderer,
  });

  final PlaybackService playbackService;
  final StageRenderer stageRenderer;

  @override
  Widget build(BuildContext context) {
    final state = playbackService.state;
    final song = state.currentSong;
    return LayoutBuilder(
      builder: (context, constraints) {
        const songStripHeight = 148.0;
        const stageGap = 22.0;
        final availableStageHeight =
            constraints.maxHeight - songStripHeight - stageGap;
        final maxStageHeight =
            availableStageHeight < 0 ? 0.0 : availableStageHeight;
        final stageHeight = maxStageHeight;

        return Column(
          children: [
            SizedBox(
              width: double.infinity,
              height: stageHeight,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: KiraColors.lineStrong),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x57000000),
                      blurRadius: 58,
                      offset: Offset(0, 22),
                    ),
                  ],
                ),
                child: Center(
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          StageScreen(
                            playbackService: playbackService,
                            stageRenderer: stageRenderer,
                          ),
                          if (!state.isPlaying)
                            Center(
                              child: FilledButton(
                                onPressed: playbackService.play,
                                style: FilledButton.styleFrom(
                                  backgroundColor: KiraColors.cream,
                                  foregroundColor: const Color(0xff17181c),
                                  shape: const CircleBorder(),
                                  fixedSize: const Size(138, 138),
                                ),
                                child: const Icon(Icons.play_arrow, size: 70),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: stageGap),
            SizedBox(
              height: songStripHeight,
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 28),
                      decoration: _surfaceDecoration(),
                      child: Row(
                        children: [
                          _SongCover(song: song, size: 98),
                          const SizedBox(width: 22),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  song?.title ?? '等待点歌',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: KiraColors.cream,
                                    fontSize: 40,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  song?.artist?.name ?? '请从右侧或手机加入歌曲',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: KiraColors.muted,
                                    fontSize: 21,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 22),
                  Container(
                    width: 268,
                    padding: const EdgeInsets.all(19),
                    decoration: _surfaceDecoration(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '升降 Key',
                          style: TextStyle(
                            color: KiraColors.muted,
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const Spacer(),
                        Row(
                          children: [
                            SquareIconButton(
                              icon: Icons.remove,
                              onPressed: () => playbackService.transposeBy(-1),
                            ),
                            Expanded(
                              child: Text(
                                state.key > 0
                                    ? '+${state.key}'
                                    : '${state.key}',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: KiraColors.amber,
                                  fontSize: 48,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            SquareIconButton(
                              icon: Icons.add,
                              onPressed: () => playbackService.transposeBy(1),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _RightPane extends StatelessWidget {
  const _RightPane({
    required this.onPanel,
  });

  final ValueChanged<String> onPanel;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: _MenuCard(
            title: '歌名点歌',
            subtitle: '按歌曲标题、编号或作品名查找',
            chips: const ['拼音', '编号', '收藏'],
            icon: Icons.music_note,
            colors: const [
              Color(0xff8f2425),
              KiraColors.red,
              Color(0xffe58c41)
            ],
            leadingStripe: true,
            onTap: () => onPanel('歌名点歌'),
          ),
        ),
        const SizedBox(height: 22),
        Expanded(
          child: _MenuCard(
            title: '歌手点歌',
            subtitle: '按歌手、社团、角色或声库筛选',
            chips: const ['歌手', '社团', '声库'],
            icon: Icons.mic_external_on,
            colors: const [
              Color(0xff2f62db),
              KiraColors.blue,
              Color(0xff70a7ff)
            ],
            onTap: () => onPanel('歌手点歌'),
          ),
        ),
        const SizedBox(height: 22),
        Expanded(
          child: _MenuCard(
            title: '分类点歌',
            subtitle: '热门、动画、同人、VOCALOID',
            chips: const ['热门', '动画', '同人', 'VOCALOID'],
            icon: Icons.library_music,
            colors: const [
              Color(0xffbb3d79),
              KiraColors.pink,
              Color(0xffff91bd)
            ],
            onTap: () => onPanel('分类点歌'),
          ),
        ),
        const SizedBox(height: 22),
        SizedBox(
          height: 148,
          child: Row(
            children: [
              Expanded(
                child: _SmallMenuCard(
                  title: '外链点歌',
                  icon: Icons.link,
                  colors: const [
                    Color(0xff281b72),
                    KiraColors.violet,
                    Color(0xff6d54d6),
                  ],
                  onTap: () => onPanel('外链点歌'),
                ),
              ),
              const SizedBox(width: 22),
              SizedBox(
                width: 148,
                child: _SmallMenuCard(
                  title: '排行榜',
                  icon: Icons.emoji_events,
                  colors: const [
                    Color(0xffa85422),
                    KiraColors.orange,
                    Color(0xfff0a258),
                  ],
                  compact: true,
                  onTap: () => onPanel('排行榜'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.playbackService,
    required this.queueService,
    required this.castService,
    required this.onQueue,
    required this.onAfterQueueChanged,
  });

  final PlaybackService playbackService;
  final QueueService queueService;
  final CastService castService;
  final VoidCallback onQueue;
  final VoidCallback onAfterQueueChanged;

  @override
  Widget build(BuildContext context) {
    final state = playbackService.state;
    return Container(
      height: 115,
      padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 18),
      decoration: const BoxDecoration(
        color: Color(0xff15161a),
        border: Border(top: BorderSide(color: KiraColors.line)),
      ),
      child: Row(
        children: [
          KtvIconButton(
            icon: Icons.queue_music,
            label: '点歌列表',
            width: 195,
            onPressed: onQueue,
          ),
          const SizedBox(width: 18),
          Container(
            width: 400,
            height: 80,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            decoration: _surfaceDecoration(color: KiraColors.surface2),
            child: Row(
              children: [
                const SizedBox(
                  width: 72,
                  child: Text(
                    '音量',
                    style: TextStyle(
                      fontSize: 25,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                SquareIconButton(
                  icon: Icons.remove,
                  size: 48,
                  onPressed: () => playbackService.changeVolumeBy(-6),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      minHeight: 12,
                      value: state.volume / 100,
                      color: KiraColors.amber,
                      backgroundColor: const Color(0xff34363d),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                SquareIconButton(
                  icon: Icons.add,
                  size: 48,
                  onPressed: () => playbackService.changeVolumeBy(6),
                ),
              ],
            ),
          ),
          const SizedBox(width: 18),
          KtvIconButton(
            icon: state.audioTrackMode == AudioTrackMode.vocal
                ? Icons.graphic_eq
                : Icons.music_note,
            label: state.audioTrackMode == AudioTrackMode.vocal ? '原唱' : '伴奏',
            width: 195,
            foregroundColor: KiraColors.teal,
            onPressed: playbackService.toggleAudioTrack,
          ),
          const Spacer(),
          SizedBox(
            width: 638,
            child: Row(
              children: [
                Expanded(
                  child: KtvIconButton(
                    icon: Icons.replay,
                    label: '重唱',
                    onPressed: playbackService.replay,
                  ),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: KtvIconButton(
                    icon: state.isPlaying ? Icons.pause : Icons.play_arrow,
                    label: state.isPlaying ? '暂停' : '播放',
                    active: true,
                    onPressed: playbackService.togglePlayPause,
                  ),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: KtvIconButton(
                    icon: Icons.skip_next,
                    label: '切歌',
                    onPressed: () {
                      playbackService.next();
                      onAfterQueueChanged();
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MenuCard extends StatelessWidget {
  const _MenuCard({
    required this.title,
    required this.subtitle,
    required this.chips,
    required this.icon,
    required this.colors,
    required this.onTap,
    this.leadingStripe = false,
  });

  final String title;
  final String subtitle;
  final List<String> chips;
  final IconData icon;
  final List<Color> colors;
  final VoidCallback onTap;
  final bool leadingStripe;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: colors),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0x3dffffff)),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (leadingStripe)
                const Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  child: ColoredBox(
                    color: Color(0xb8ffffff),
                    child: SizedBox(width: 10),
                  ),
                ),
              const Positioned(
                right: -48,
                bottom: -68,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Color(0x1fffffff),
                    shape: BoxShape.circle,
                  ),
                  child: SizedBox(width: 212, height: 212),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 35),
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
                              fontSize: 50,
                              height: 1,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 11),
                          Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xcaffffff),
                              fontSize: 19,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 15),
                          Wrap(
                            spacing: 9,
                            runSpacing: 5,
                            children: [
                              for (final chip in chips)
                                Container(
                                  height: 30,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 11,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0x29ffffff),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    chip,
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 22),
                    Icon(icon, size: 72, color: const Color(0xeaffffff)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SmallMenuCard extends StatelessWidget {
  const _SmallMenuCard({
    required this.title,
    required this.icon,
    required this.colors,
    required this.onTap,
    this.compact = false,
  });

  final String title;
  final IconData icon;
  final List<Color> colors;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: colors),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0x3dffffff)),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              const Positioned(
                right: -48,
                bottom: -68,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Color(0x1fffffff),
                    shape: BoxShape.circle,
                  ),
                  child: SizedBox(width: 212, height: 212),
                ),
              ),
              Center(
                child: compact
                    ? Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(icon, size: 38),
                          const SizedBox(height: 9),
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 21,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(icon, size: 40),
                          const SizedBox(width: 15),
                          Flexible(
                            child: Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 34,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
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
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: 60,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          backgroundColor: KiraColors.surface2,
          foregroundColor: KiraColors.cream,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: const BorderSide(color: KiraColors.line),
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

class _SongCover extends StatelessWidget {
  const _SongCover({
    required this.song,
    required this.size,
  });

  final Song? song;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = Color(song?.coverColor ?? 0xffdd3e38);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withValues(alpha: 0.9),
            KiraColors.amber.withValues(alpha: 0.5),
          ],
        ),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0x29ffffff)),
      ),
      child: const Icon(
        Icons.music_note,
        color: KiraColors.cream,
      ),
    );
  }
}

class _KiraDialog extends StatelessWidget {
  const _KiraDialog({
    required this.title,
    required this.child,
    this.width = 430,
  });

  final String title;
  final Widget child;
  final double width;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xff17181c),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: KiraColors.lineStrong),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: width),
        child: Padding(
          padding: const EdgeInsets.all(26),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: KiraColors.cream,
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '关闭',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, color: KiraColors.amber),
          const SizedBox(width: 12),
          SizedBox(
            width: 86,
            child: Text(
              label,
              style: const TextStyle(
                color: KiraColors.muted,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _QueueItemRow extends StatelessWidget {
  const _QueueItemRow({
    required this.index,
    required this.song,
    required this.subtitle,
    required this.isCurrent,
    this.onBump,
    this.onDelete,
  });

  final int index;
  final Song song;
  final String subtitle;
  final bool isCurrent;
  final VoidCallback? onBump;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isCurrent ? KiraColors.teal : KiraColors.surface2,
              borderRadius: BorderRadius.circular(10),
            ),
            child: isCurrent
                ? Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: KiraColors.bg,
                      shape: BoxShape.circle,
                    ),
                  )
                : Text(
                    index.toString().padLeft(2, '0'),
                    style: const TextStyle(
                      color: KiraColors.amber,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  song.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isCurrent
                        ? KiraColors.cream.withValues(alpha: 0.72)
                        : KiraColors.cream,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: KiraColors.muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          if (isCurrent)
            Container(
              height: 24,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: const Color(0x2422c59b),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: const Color(0x4722c59b)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.circle, size: 6, color: KiraColors.teal),
                  SizedBox(width: 4),
                  Text(
                    '播放中',
                    style: TextStyle(
                      color: KiraColors.teal,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            )
          else ...[
            if (onBump != null)
              _QueueIconButton(
                icon: Icons.arrow_upward,
                color: KiraColors.muted,
                tooltip: '顶到下一首',
                onTap: onBump,
              ),
            const SizedBox(width: 6),
            if (onDelete != null)
              _QueueIconButton(
                icon: Icons.close,
                color: KiraColors.muted,
                tooltip: '移除',
                onTap: onDelete,
              ),
          ],
        ],
      ),
    );
  }
}

class _QueueIconButton extends StatelessWidget {
  const _QueueIconButton({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: KiraColors.surface2,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: KiraColors.line),
            ),
            child: Icon(icon, size: 18, color: color),
          ),
        ),
      ),
    );
  }
}

BoxDecoration _surfaceDecoration({Color color = KiraColors.surface}) {
  return BoxDecoration(
    color: color,
    borderRadius: BorderRadius.circular(10),
    border: Border.all(color: KiraColors.line),
    boxShadow: const [
      BoxShadow(
        color: Color(0x38000000),
        blurRadius: 32,
        offset: Offset(0, 12),
      ),
    ],
  );
}
