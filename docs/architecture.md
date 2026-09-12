# Kirakara-App Architecture

## Product Split

Kirakara-App is a local-first KTV host. Room state belongs to the local app.
Catalog and asset authority belongs to a catalog/resource server, which may be a
local LAN server, a NAS-style server, or a future cloud catalog.

Local authority state:

- playback queue
- current song
- play / pause / replay / skip
- key
- vocal / accompaniment mode
- volume and playback progress

Catalog/resource server authority:

- catalog metadata
- taxonomy and category membership
- rankings and sub-rankings
- KRL lyric projects and versions
- media and cover asset versions
- resource URI, hash, size, and revision metadata

The server may add, remove, or replace media files and KRL projects at any time.
The app must not treat cached resource bytes as authoritative.

Local persistent data:

- last synced taxonomy / ranking / catalog index manifests
- local search index, such as SQLite FTS or another local index
- app settings, display preferences, and input/search history
- optional local user aliases or personal tags

Local volatile playback cache:

- media files or streams required by the current playback cycle
- covers and KRL files required by the current playback cycle
- decoded or prepared assets needed by the current StageRenderer session

Asset cache is disposable. It should be cleared after playback, app exit, cache
pressure, or a server version/hash mismatch. It is not an offline song library.

## Playback Media I/O

`PlaybackAssetCache` owns policy, not byte transport. It keeps the public asset
API, the 15-permit global connection pool, song priorities, latest-lowest
priority preemption, retry policy, and the main-isolate metadata mirror.

Production byte transport follows this order:

1. On Windows, negotiate the process-local `kirakara/media_io` bridge once.
   WinHTTP worker threads read network data into bounded buffers and write
   `.part` files directly. A single 4 Hz poll is active only while native
   downloads exist; media chunks never cross the platform channel.
2. If that bridge is unavailable, use one long-lived Dart media I/O isolate.
   The isolate owns its HTTP clients, batched file writers, and the progressive
   loopback HTTP server. Only commands and low-rate progress snapshots cross
   back to Flutter.
3. Injected HTTP clients use the same bounded Dart stream pump in the caller
   isolate. This path exists for deterministic tests and custom embedders.

All paths are unlimited-rate transfers. Backpressure pauses only a source whose
bounded write buffer is full; it is not bandwidth throttling. The first video
runway is persisted promptly, later Windows writes are normally 1 MiB but have
a 200 ms visibility bound for partial batches, completed files use `addStream`,
and remote range proxying never flushes once per source chunk. The progressive
server also tracks whether the matching producer is active, so a slow
sub-batch tail cannot be mistaken for a dead download and truncate Media
Foundation's response.

Capability results, counters, URLs, request headers, and cookies are never
persisted by this subsystem. Native capability failure is remembered only for
the current `PlaybackAssetCache` lifetime. `PlaybackAssetIoDiagnostics` stores
aggregate byte/call/connection counters in memory and logs only when explicitly
requested in a debug build.

Regression commands:

```powershell
flutter test test/services_test.dart test/playback_media_io_worker_test.dart test/windows_native_media_io_test.dart
flutter test integration_test/media_io_integration_test.dart -d windows
flutter build windows --release
```

Playback duration and auto-advance should come from the actual selected audio
stream/file after it is opened. The server does not need to send duration
metadata.

## Screens

Controller Screen:

- touch-first ordering and control UI
- search, queue, settings, playback control
- may show a small Stage preview for single-screen operation

Stage Screen:

- pure 16:9 KTV output
- no ordering UI, search UI, settings UI, or queue UI
- driven by `PlaybackService` and `StageRenderer`
- hosted by the KiraKara-Show native renderer on Windows

Phone Screen:

- LAN-only web UI served by the app's embedded HTTP server
- queues songs into the same local `QueueService`
- never writes room state to a public cloud service

## Display Strategy

Single-screen mode:

- Controller UI is shown in the app window.
- Stage output can be previewed inside the controller.
- Optional casting must use `CastService` and a `StageRenderer` frame stream,
  not a mirrored controller UI.

Dual-screen mode:

- primary display hosts Controller Screen.
- secondary display hosts a fullscreen Stage Screen.
- `DisplayManager` owns display detection and user preference.
- KiraKara-Show owns the native Stage window and render surfaces.

Wireless Cast mode:

- mutually exclusive with physical dual-screen output
- uses the same ShowHost playback authority and Stage program semantics
- renders a fixed 1920x1080 offscreen Stage texture instead of capturing a
  Controller or Stage HWND
- streams H.264 plus processed AAC audio as continuous MPEG-TS; pause, replay,
  seek, and next change program content without replacing the receiver URL

Debug mode:

- a preview window or embedded preview can simulate Stage Output.
- Stage rendering remains independent from controller widgets.

## Remaining Replacement Points

- `LanServer` mock JSON endpoints -> phone ordering web app and API
- `MockCatalogClient` -> local/cloud catalog client with manifest and delta
  sync
- `CacheService` mock state -> persistent index cache plus disposable playback
  asset cache
- `DisplayManager` Windows display enumeration -> Android display backend
- `CastService` Windows DLNA control point -> Android DLNA control backend
