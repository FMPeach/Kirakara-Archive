# Engine patch stack

The root build records in `engine.lock.json` preserve the patch-free Phase 1
baseline. Phase 2 adds the v2 `0001-windows-dcomp-synthetic-compositor.patch`, an
opt-in Windows-only technical probe containing the versioned ABI, premultiplied
Flutter composition surface, two-Visual DComp tree, independent synthetic D3D
producer, in-place swapchain resize that preserves the visual tree, and bounded
diagnostics tests.

Every patch entry names its relative path and SHA-256, and the lock also records
the exact Git tree produced by the whole ordered stack. The application script
can apply or reverse only that exact stack, so extra Engine source edits are a
hard error. Real Show attachment, lifecycle recovery, damage/idle work and the
clipboard track remain separate future patches. Engine binaries, symbols and
build directories do not belong here or in normal Git history.
