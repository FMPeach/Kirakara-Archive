# Engine patch stack

The root build records in `engine.lock.json` preserve the patch-free Phase 1
baseline. The ordered v5 stack contains two independently reviewable patches:

- `0001-windows-dcomp-stage-visual-compositor.patch` contains the versioned ABI,
  premultiplied Flutter composition surface, two-Visual DComp tree, independent
  synthetic D3D producer, external latest-frame Stage consumer, in-place
  swapchain resize that preserves the visual tree, a one-shot opaque-black
  external Stage placeholder before Show publishes its first frame, and
  bounded diagnostics tests.
- `0002-windows-clipboard-contention.patch` keeps Flutter's public Clipboard API
  unchanged while adding a temporary 16 ms message-window timer for
  `ERROR_ACCESS_DENIED` only. It stops after 16 attempts or 250 ms, whichever
  comes first, rejects text above 1 Mi UTF-16 code units before Dart, cancels
  pending calls explicitly during teardown, and never logs clipboard content.

Every patch entry names its relative path and SHA-256, and the lock also records
the exact Git tree produced by the whole ordered stack. The application script
can apply or reverse only that exact stack, so extra Engine source edits are a
hard error. Phase 4 window/session/power activity and transactional Show source
ownership, plus Phase 5 visibility/VFR gates, live in the Runner and do not
require another Engine patch. Actual graphics-device-loss recovery remains a
separate compatibility task. Engine binaries, symbols and build directories do
not belong here or in normal Git history.
