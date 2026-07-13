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

## Replacement Points

- `MockStageRenderer` -> KiraKara-Show native renderer / texture
- `SearchService` mock list -> repository backed by synced catalog index and
  SQLite FTS or equivalent
- `LanServer` mock JSON endpoints -> phone ordering web app and API
- `MockCatalogClient` -> local/cloud catalog client with manifest and delta
  sync
- `CacheService` mock state -> persistent index cache plus disposable playback
  asset cache
- `DisplayManager` Windows display enumeration -> Android display backend
- `CastService` Windows DLNA control point -> Android DLNA control backend
