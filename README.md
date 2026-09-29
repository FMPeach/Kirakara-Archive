## 本软件暂未上线，目前暂未到可用程度，敬请期待。


# Kirakara-App

Local-first KTV host app prototype for Windows and Android tablets.

This first slice keeps the controller UI, stage output, playback state, queue,
LAN API, cast service, and native renderer seams separated. It uses mock
catalog/search data while the playback preview is moving toward the
KiraKara-Show native host.

## Data Direction

- The app is the only authority for room state: queue, current playback, key,
  vocal/accompaniment mode, volume, pause, replay, and skip.
- The catalog/resource server is the authority for song indexes, taxonomy,
  rankings, asset versions, media files, covers, and KRL files.
- Local persistent storage is for synced manifests, search indexes, settings,
  and local user data. Media, covers, and KRL files are playback-cycle cache,
  not a local offline library.
- Server resources may be added, removed, or replaced at any time. Cached asset
  bytes must be treated as disposable and revalidated through server-provided
  version/hash metadata.
- The server does not need to provide duration metadata. Playback duration and
  auto-advance should come from the actual selected audio stream/file.

## Run

```powershell
flutter create --platforms=windows,android .
flutter pub get
flutter run -d windows
```

If the Flutter SDK is already on PATH, the `flutter create` command will add the
platform folders without replacing the app code in `lib/`.

## Architecture Notes

- Controller Screen is the touch/order/control surface.
- Stage Screen is the pure singing output and does not depend on controller UI.
- Phone Screen is reserved for LAN-only browser ordering through `LanServer`.
- `PlaybackService` owns room playback state: current song, key, vocal/accompaniment,
  play/pause, volume, and progress.
- `QueueService` owns local queue state. Cloud services never store room state.
- `DisplayManager`, `StageWindow`, `StageRenderer`, and `CastService` are early
  abstractions for native dual-screen output and mock single-window preview.
- `CacheService` should distinguish persistent catalog/search index cache from
  disposable playback asset cache.
