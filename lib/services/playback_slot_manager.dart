import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../domain/media_asset.dart';
import '../domain/queue_item.dart';
import '../domain/song.dart';
import 'playback_asset_cache.dart';
import 'playback_slot.dart';
import 'queue_service.dart';

/// 准无缝切歌架构的核心。
///
/// 保持 active + standby 两个 [PlaybackSlot]。
/// 切歌热路径只做 slot swap；下载、DB 查询、KRL 解析均在后台准备。
class PlaybackSlotManager extends ChangeNotifier {
  PlaybackSlotManager({
    required QueueService queueService,
    PlaybackAssetCache? assetCache,
  })  : _queueService = queueService,
        _assetCache = assetCache {
    _queueService.addListener(_onQueueChanged);
  }

  final QueueService _queueService;
  final PlaybackAssetCache? _assetCache;

  PlaybackSlot? _activeSlot;
  PlaybackSlot? _standbySlot;
  int _prepGeneration = 0;

  // ── 暴露给 UI ─────────────────────────────────────────────────

  /// 下一首的准备状态。
  SlotState get upNextState => _standbySlot?.state ?? SlotState.empty;

  /// 已准备的下一首 songId。
  String? get preparedSongId =>
      _standbySlot?.isReady == true ? _standbySlot?.songId : null;

  /// 最近一次准备失败的信息。
  String? get lastPreparationError =>
      _standbySlot?.state == SlotState.failed ? _standbySlot?.error : null;

  PlaybackSlot? get activeSlot => _activeSlot;

  // ── 生命周期 ──────────────────────────────────────────────────

  @override
  void dispose() {
    _queueService.removeListener(_onQueueChanged);
    super.dispose();
  }

  // ── 队列变化 ──────────────────────────────────────────────────

  void _onQueueChanged() {
    _maybePrepareNext();
  }

  /// 在 active 开始播放后调用，启动 standby 预热。
  void onPlaybackStarted() {
    _maybePrepareNext();
  }

  void _maybePrepareNext() {
    final nextItem = _peekNextQueueItem();
    if (nextItem == null) {
      // 队列空了，清 standby
      if (_standbySlot != null && _standbySlot!.songId != _activeSlot?.songId) {
        _standbySlot = null;
        notifyListeners();
      }
      return;
    }

    final nextId = nextItem.song.id;
    // 如果 standby 已经是同一首且 ready/preparing，不重复准备
    if (_standbySlot != null &&
        _standbySlot!.songId == nextId &&
        (_standbySlot!.isReady || _standbySlot!.state == SlotState.preparing)) {
      return;
    }

    _prepareStandby(nextItem);
  }

  // ── 准备 standby ──────────────────────────────────────────────

  Future<void> _prepareStandby(QueueItem item) async {
    final gen = ++_prepGeneration;
    final isExternal = item.song.isExternal;
    final slot = PlaybackSlot(songId: item.song.id)
      ..state = SlotState.preparing
      ..generation = gen
      ..song = item.song;

    _standbySlot = slot;
    notifyListeners();

    try {
      // 1) 下载资源 — 外部歌曲跳过（视频是 HTTP URL，直接给引擎拉流）
      if (!isExternal && _assetCache != null) {
        await _assetCache.ensureSongAssets(item.song);
      }
      if (_isStale(gen)) return;

      // 2) 收集本地路径
      slot.videoPath = _pathFor(item.song, MediaAssetType.video);
      slot.vocalPath = isExternal ? null : _existingPathFor(item.song, MediaAssetType.vocal);
      slot.instPath = isExternal ? null : _existingPathFor(item.song, MediaAssetType.accompaniment);
      slot.krlPath = isExternal ? null : (item.song.lyricProject?.cachedPath ??
          _pathFor(item.song, MediaAssetType.lyric));

      // 外部歌曲只需 videoPath；普通歌曲需要 video + krl
      if (slot.videoPath == null || (!isExternal && slot.krlPath == null)) {
        slot.state = SlotState.failed;
        slot.error = isExternal ? 'missing video URL' : 'missing media or KRL';
        notifyListeners();
        return;
      }

      if (_isStale(gen)) return;

      slot.state = SlotState.ready;
      notifyListeners();
      debugPrint('PlaybackSlotManager: standby ready for ${item.song.title}');
    } catch (e) {
      if (_isStale(gen)) return;
      slot.state = SlotState.failed;
      slot.error = e.toString();
      notifyListeners();
    }
  }

  // ── 切歌：promote standby → active ────────────────────────────

  /// 切歌热路径。如果 standby ready 且匹配，直接返回准备好的 slot。
  /// 否则返回 null，调用方走 fallback 慢路径。
  PlaybackSlot? consumeStandby(String nextSongId) {
    final standby = _standbySlot;
    if (standby == null) return null;
    if (!standby.isReady) return null;
    if (standby.songId != nextSongId) return null;

    _activeSlot = standby;
    _standbySlot = null;
    notifyListeners();

    // 异步准备新的下一首
    Future.microtask(_maybePrepareNext);

    return _activeSlot;
  }

  // ── fallback：同步创建临时 active slot ─────────────────────────

  /// 当 standby 未就绪时，创建一个标记为 empty 的 active slot。
  /// 调用方之后需要走完整下载+加载流程。
  PlaybackSlot createFallbackActive(String songId, Song song) {
    _activeSlot = PlaybackSlot(songId: songId)
      ..song = song
      ..state = SlotState.empty;
    _standbySlot = null;
    notifyListeners();
    return _activeSlot!;
  }

  // ── helpers ───────────────────────────────────────────────────

  QueueItem? _peekNextQueueItem() {
    final items = _queueService.items;
    return items.isNotEmpty ? items.first : null;
  }

  String? _pathFor(Song song, MediaAssetType type) {
    for (final asset in song.assets) {
      if (asset.type != type) continue;
      if (asset.cachedPath != null && asset.cachedPath!.isNotEmpty) {
        return asset.cachedPath;
      }
      // HTTP(S) URL 直接返回（外部歌曲流媒体）
      if (asset.uri.isScheme('http') || asset.uri.isScheme('https')) {
        return asset.uri.toString();
      }
      if (asset.uri.isScheme('file')) {
        return asset.uri.toFilePath(windows: Platform.isWindows);
      }
    }
    return null;
  }

  String? _existingPathFor(Song song, MediaAssetType type) {
    final path = _pathFor(song, type);
    if (path == null || !File(path).existsSync()) return null;
    return path;
  }

  bool _isStale(int generation) =>
      generation != _prepGeneration || _standbySlot?.generation != generation;
}
