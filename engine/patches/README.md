# Engine patch stack

The root build records in `engine.lock.json` preserve the patch-free Phase 1
baseline. The current v3 `0001-windows-dcomp-stage-visual-compositor.patch`
contains the versioned ABI, premultiplied Flutter composition surface,
two-Visual DComp tree, independent synthetic D3D producer, external latest-frame
Stage consumer, in-place swapchain resize that preserves the visual tree, and
bounded diagnostics tests.

Every patch entry names its relative path and SHA-256, and the lock also records
the exact Git tree produced by the whole ordered stack. The application script
can apply or reverse only that exact stack, so extra Engine source edits are a
hard error. Phase 4 window/session/power activity and transactional Show source
ownership live in the Runner and do not require another Engine patch. Actual
graphics-device-loss recovery, damage/idle work and the clipboard track remain
separate follow-up patches. Engine binaries, symbols and build directories do
not belong here or in normal Git history.
