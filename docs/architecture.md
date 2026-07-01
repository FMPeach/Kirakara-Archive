# Kirakara-App Architecture

## Product Split

Kirakara-App is a local-first KTV host. The cloud catalog can help synchronize
song metadata, KRL projects, media, covers, and versions, but room state belongs
to the local app.

Local authority state:

- playback queue
- current song
- play / pause / replay / skip
- key
- vocal / accompaniment mode
- volume and playback progress

Cloud-assisted data:

- catalog metadata
- KRL lyric projects
- media asset versions
- cover art

## Screens

Controller Screen:

- touch-first ordering and control UI
- search, queue, settings, playback control
- may show a small Stage preview for single-screen operation

Stage Screen:

- pure 16:9 KTV output
- no ordering UI, search UI, settings UI, or queue UI
- driven by `PlaybackService` and `StageRenderer`
- future host for KiraKara-Show native texture / C++ renderer

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
- `StageWindowHost` is the future native multi-window boundary.

Debug mode:

- a preview window or embedded preview can simulate Stage Output.
- Stage rendering remains independent from controller widgets.

## Replacement Points

- `MockStageRenderer` -> KiraKara-Show native renderer / texture
- `SearchService` mock list -> repository backed by SQLite FTS
- `LanServer` mock JSON endpoints -> phone ordering web app and API
- `MockCatalogClient` -> cloud catalog sync client
- `DisplayManager` mock display list -> Windows / Android native display APIs
- `CastService` mock state -> DLNA / cast output pipeline
