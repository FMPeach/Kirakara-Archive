import 'dart:async';

import 'package:flutter/material.dart';

import '../data/catalog/catalog_client.dart';
import '../data/local_db/local_database.dart';
import '../engine/kirakara_stage_renderer.dart';
import '../engine/stage_renderer.dart';
import '../services/cast_service.dart';
import '../services/display_manager.dart';
import '../services/kirakara_show_service.dart';
import '../services/lan_server.dart';
import '../services/playback_asset_cache.dart';
import '../services/playback_service.dart';
import '../services/playback_slot_manager.dart';
import '../services/queue_service.dart';
import '../services/search_service.dart';
import '../services/settings_service.dart';
import '../ui/shell/controller_services.dart';
import '../ui/shell/controller_shell.dart';
import '../ui/theme/kirakara_theme.dart';

class KirakaraApp extends StatefulWidget {
  const KirakaraApp({super.key});

  @override
  State<KirakaraApp> createState() => _KirakaraAppState();
}

class _KirakaraAppState extends State<KirakaraApp> {
  late final LocalDatabase _localDb;
  late final HttpCatalogClient _catalogClient;
  late final SearchService searchService;
  late final QueueService queueService;
  late final PlaybackService playbackService;
  late final DisplayManager displayManager;
  late final CastService castService;
  late final LanServer lanServer;
  late final PlaybackAssetCache _assetCache;
  late final PlaybackSlotManager _slotManager;
  late final SettingsService settingsService;
  late final KirakaraShowService kirakaraShowService;
  late final StageRenderer stageRenderer;

  @override
  void initState() {
    super.initState();
    _localDb = LocalDatabase();
    _localDb.open(); // 同步打开，确保 SearchService 可用
    _catalogClient = HttpCatalogClient(
      baseUrl: Uri.parse('http://localhost:7392'),
    );
    _assetCache = PlaybackAssetCache(
      baseUrl: 'http://localhost:7392',
    );

    // 先用 fallback 数据初始化 SearchService，等同步完成后再刷新
    searchService = SearchService(db: _localDb);
    queueService = QueueService();

    for (final song in searchService.featuredSongs.take(3)) {
      queueService.addSong(song);
    }
    final first = queueService.takeNext();
    playbackService = PlaybackService(
      queueService: queueService,
      initialItem: first,
    );
    playbackService.refreshUpNext();
    _slotManager = PlaybackSlotManager(
      queueService: queueService,
      assetCache: _assetCache,
    );
    settingsService = SettingsService()..addListener(_applySettings);
    unawaited(settingsService.load());
    kirakaraShowService = KirakaraShowService(
      playbackService: playbackService,
      assetCache: _assetCache,
      slotManager: _slotManager,
    )..start();
    displayManager = DisplayManager();
    castService = CastService(showService: kirakaraShowService);
    lanServer = LanServer(
      queueService: queueService,
      searchService: searchService,
      playbackService: playbackService,
    );
    stageRenderer = KirakaraStageRenderer(showService: kirakaraShowService);
    unawaited(_initializeDisplayOutput());
    unawaited(_syncCatalog());
  }

  Future<void> _syncCatalog() async {
    try {
      final manifest = await _catalogClient.fetchManifest();
      _localDb.replaceAll(manifest);
      searchService.labelMaps = manifest.labelMaps;
      searchService.invalidateCache();
      if (mounted) {
        setState(() {
          // SearchService 下次读取 featuredSongs 时自动从 DB 取
        });
      }
    } catch (e) {
      debugPrint('Catalog sync failed, using fallback data: $e');
    }
  }

  void _applySettings() {
    _slotManager.setPrefetchLookahead(settingsService.prefetchLookahead);
  }

  Future<void> _initializeDisplayOutput() async {
    await displayManager.detectDisplays();
    if (!mounted) return;

    final stageDisplay = displayManager.stageDisplay;
    if (stageDisplay == null) {
      kirakaraShowService.setStageWindowVisible(false);
      return;
    }

    kirakaraShowService.setStageWindowRect(
      x: stageDisplay.left,
      y: stageDisplay.top,
      width: stageDisplay.width,
      height: stageDisplay.height,
    );
    await displayManager.openStageWindow(preview: false);
    kirakaraShowService.setStageWindowVisible(true);
  }

  @override
  void dispose() {
    unawaited(kirakaraShowService.dispose());
    playbackService.disposeService();
    lanServer.stop();
    _slotManager.dispose();
    settingsService
      ..removeListener(_applySettings)
      ..dispose();
    _assetCache.clear();
    _assetCache.dispose();
    _catalogClient.dispose();
    _localDb.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Kira Karaoke',
      theme: buildKirakaraTheme(),
      home: ControllerShell(
        services: ControllerServices(
          searchService: searchService,
          queueService: queueService,
          playbackService: playbackService,
          assetCache: _assetCache,
          slotManager: _slotManager,
          settingsService: settingsService,
          displayManager: displayManager,
          kirakaraShowService: kirakaraShowService,
          castService: castService,
          lanServer: lanServer,
          stageRenderer: stageRenderer,
        ),
      ),
    );
  }
}
