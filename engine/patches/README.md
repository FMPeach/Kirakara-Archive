# Engine patch stack

Phase 1 intentionally has no patches. `engine.lock.json` therefore records the
patchset as `stock`, version `0`, with an empty patch list.

Later phases add numbered, reviewable patches here. Every lock entry must name
the relative patch path and its SHA-256. Engine binaries, symbols and build
directories do not belong in this directory or in normal Git history.
