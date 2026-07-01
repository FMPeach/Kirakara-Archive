# Kirakara-App

Local-first KTV host app prototype for Windows and Android tablets.

This first slice keeps the controller UI, stage output, playback state, queue,
LAN API, cast service, and future native renderer seams separated. It uses mock
catalog/search data and a Flutter canvas-style stage renderer so the app can run
without cloud services or the future KiraKara-Show native engine.

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
