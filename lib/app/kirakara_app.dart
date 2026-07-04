import 'dart:async';

import 'package:flutter/material.dart';

import '../engine/kirakara_stage_renderer.dart';
import '../engine/stage_renderer.dart';
import '../services/cast_service.dart';
import '../services/catalog_client.dart';
import '../services/display_manager.dart';
import '../services/kirakara_show_service.dart';
import '../services/lan_server.dart';
import '../services/playback_service.dart';
import '../services/queue_service.dart';
import '../services/search_service.dart';
import '../ui/screens/controller_screen.dart';
import '../ui/theme/kirakara_theme.dart';

class KirakaraApp extends StatefulWidget {
  const KirakaraApp({super.key});

  @override
  State<KirakaraApp> createState() => _KirakaraAppState();
}

class _KirakaraAppState extends State<KirakaraApp> {
  late final SearchService searchService;
  late final QueueService queueService;
  late final PlaybackService playbackService;
  late final DisplayManager displayManager;
  late final CastService castService;
  late final LanServer lanServer;
  late final KirakaraShowService kirakaraShowService;
  late final MockCatalogClient catalogClient;
  late final StageRenderer stageRenderer;

  @override
  void initState() {
    super.initState();
    searchService = SearchService();
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
    kirakaraShowService = KirakaraShowService(
      playbackService: playbackService,
    )..start();
    displayManager = DisplayManager()..detectDisplays();
    castService = CastService();
    lanServer = LanServer(
      queueService: queueService,
      searchService: searchService,
    );
    catalogClient = const MockCatalogClient();
    stageRenderer = KirakaraStageRenderer(showService: kirakaraShowService);
  }

  @override
  void dispose() {
    unawaited(kirakaraShowService.dispose());
    playbackService.disposeService();
    lanServer.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Kira Karaoke',
      theme: buildKirakaraTheme(),
      home: ControllerScreen(
        searchService: searchService,
        queueService: queueService,
        playbackService: playbackService,
        displayManager: displayManager,
        kirakaraShowService: kirakaraShowService,
        castService: castService,
        lanServer: lanServer,
        stageRenderer: stageRenderer,
      ),
    );
  }
}
