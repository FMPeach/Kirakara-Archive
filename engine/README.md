# Kirakara Windows Flutter Engine

This directory contains only the reproducibility contract for the custom
Windows Flutter Engine. Engine source, `out/`, DLLs, import libraries, symbols
and downloaded toolchains must remain in an external workspace or a versioned
release artifact. They must not be committed to the App repository.

The root `builds` entries preserve the completely stock Phase 1 artifacts for
Flutter 3.44.4. `patchset` separately locks the Phase 2/3 Kirakara source patch,
its resulting Git tree, additional public export and custom debug artifacts.
Switching variants never edits the installed Flutter SDK and never removes the
other variant's `out/` directory.

## Pinned layout

The scripts use this external layout, with the root supplied at runtime:

```text
E:\Kirakara-Flutter-Engine\
├─ depot_tools\
└─ flutter\
   ├─ .gclient
   └─ engine\src\out\
      ├─ host_debug\
      ├─ host_profile\
      ├─ host_release\
      └─ host_debug_kirakara_v3\
```

No absolute host path is stored in `engine.lock.json`. The example uses E: only
because it has enough free space and keeps the checkout path short.

## Fetch and synchronize

Run from a normal PowerShell first. On Windows, upstream documents an
administrator requirement for some `gclient` setups; elevate only if the
command reports the corresponding permission failure.

```powershell
Set-Location 'D:\Kirakara-App-ascii'
.\engine\scripts\fetch_engine.ps1 `
  -WorkspaceRoot 'E:\Kirakara-Flutter-Engine' `
  -VisualStudioPath 'D:\Program Files\Microsoft Visual Studio\Community\2026'
```

The default path clones the exact locked depot_tools revision. If that Git
endpoint is unavailable, download the official archive named in the lock and
pass `-DepotToolsArchivePath`; the script refuses an archive whose SHA-256 does
not match. If the current network requires a proxy, pass its URL explicitly with
`-ProxyUrl`; the value is process-scoped and is not written to the repository.

## Apply patches and build

The official Flutter DLL was linked with MSVC 14.34. The lock pins the matching
side-by-side toolset to `14.34.31933` (compiler `19.34.31948.0`). The Windows
embedder also links ATL, so the lock includes both the 14.34 x86/x64 compiler
component and the matching ATL component. If either is missing, install only
those pinned components from an ordinary PowerShell; the script relaunches
itself through UAC and does not remove the newer toolset:

```powershell
.\engine\scripts\install_pinned_msvc_toolset.ps1 `
  -VisualStudioPath 'D:\Program Files\Microsoft Visual Studio\Community\2026'
```

Start from the exact stock checkout, apply the locked patchset, then build the
custom output under its own target directory:

```powershell
.\engine\scripts\apply_patches.ps1 `
  -WorkspaceRoot 'E:\Kirakara-Flutter-Engine' `
  -Variant patched

.\engine\scripts\build_windows_engine.ps1 `
  -WorkspaceRoot 'E:\Kirakara-Flutter-Engine' `
  -Variant patched `
  -Mode debug `
  -VisualStudioPath 'D:\Program Files\Microsoft Visual Studio\Community\2026'
```

The transition refuses a patch hash mismatch, unexpected source edit, or tree
that is neither exactly stock nor exactly the locked patchset. To rebuild a
stock output, reverse only the known patch stack and select the stock variant:

```powershell
.\engine\scripts\apply_patches.ps1 `
  -WorkspaceRoot 'E:\Kirakara-Flutter-Engine' `
  -Variant stock

.\engine\scripts\build_windows_engine.ps1 `
  -WorkspaceRoot 'E:\Kirakara-Flutter-Engine' `
  -Variant stock `
  -Mode debug,profile,release `
  -VisualStudioPath 'D:\Program Files\Microsoft Visual Studio\Community\2026'
```

Reapply `-Variant patched` before continuing custom Engine work. Stock builds
use the upstream `windows/host_debug`, `windows/host_profile` and
`windows/host_release` configurations; the Phase 3 patch currently locks only
`host_debug_kirakara_v3`. Both paths disable RBE and never copy Engine products
into this repository. Verification rejects a generated `toolchain.ninja` or PE
linker version that does not use the locked 14.34 toolset.

This pinned Engine source requires Windows SDK `10.0.22621.0`; newer SDKs do
not substitute for it because upstream's stock toolchain script explicitly
selects that version. The build script checks the required headers, x64
libraries and tools before invoking GN.

## Verify and switch the App

```powershell
.\engine\scripts\verify_engine_bundle.ps1 `
  -WorkspaceRoot 'E:\Kirakara-Flutter-Engine' `
  -FlutterSdkRoot 'D:\Program Files\Flutter' `
  -Variant patched `
  -Mode debug `
  -RequireLockedHashes

# Local stock Engine
.\engine\scripts\build_windows_app.ps1 `
  -FlutterSdkRoot 'D:\Program Files\Flutter' `
  -Engine local `
  -LocalVariant stock `
  -WorkspaceRoot 'E:\Kirakara-Flutter-Engine' `
  -Mode profile

# Local patched Engine
.\engine\scripts\build_windows_app.ps1 `
  -FlutterSdkRoot 'D:\Program Files\Flutter' `
  -Engine local `
  -LocalVariant patched `
  -WorkspaceRoot 'E:\Kirakara-Flutter-Engine' `
  -Mode debug

# Official cached Engine; no local-engine flags are passed.
.\engine\scripts\build_windows_app.ps1 `
  -FlutterSdkRoot 'D:\Program Files\Flutter' `
  -Engine official `
  -Mode profile
```

All modes use the same pinned Flutter SDK. `official`, `local/stock` and
`local/patched` are explicit A/B selections; no DLL is patched or hooked after
linking. Every App build also extracts resource `#1` from the final executable
with the locked Windows SDK `mt.exe` and requires the embedded DPI awareness to
be exactly `PerMonitorV2`, including official and local stock bundles. The
verifier writes reports below the ignored
`build/diagnostics/engine` directory. Locked sizes and SHA-256 values identify
the exact accepted artifact set, and `-RequireLockedHashes` is the gate.

The upstream stock Windows link is not bit-for-bit reproducible: PE link
timestamps and CodeView/PDB identities change on a rebuild even when the
source, GN arguments and toolchain are unchanged. The raw SHA-256 values in
the lock therefore identify the exact accepted artifact set; they are not a
claim that a later stock rebuild will have the same bytes. After an intentional
rebuild, capture every candidate value without modifying the lock:

```powershell
.\engine\scripts\verify_engine_bundle.ps1 `
  -WorkspaceRoot 'E:\Kirakara-Flutter-Engine' `
  -FlutterSdkRoot 'D:\Program Files\Flutter' `
  -Variant patched `
  -Mode debug `
  -ReportPath '.\build\diagnostics\engine\candidate-artifacts.json' `
  -CaptureArtifactHashes
```

That diagnostic mode still enforces revisions, the exact selected source tree,
`args.gn`, MSVC selection, PE linker version and official/local exports. For a
patched build, every official export must remain and only the additions named
in the lock are allowed. It reports every artifact difference, emits a warning
and never edits `engine.lock.json`.
Relocking is a separate reviewed source change: inspect the candidate report,
write only the accepted values into the lock, rerun with
`-RequireLockedHashes`, and then run the unit and App A/B gates. A candidate is
not distributable unless every gate passes; a failed gate requires rejecting
or fixing that explicit lock change. The two verifier switches are mutually
exclusive, and no script auto-accepts new hashes.

The debug Engine also has a bounded, log-preserving unit-test gate:

```powershell
.\engine\scripts\test_stock_windows_engine.ps1 `
  -WorkspaceRoot 'E:\Kirakara-Flutter-Engine' `
  -Suite critical,compositor,adapter-isolated

.\engine\scripts\test_patched_windows_engine.ps1 `
  -WorkspaceRoot 'E:\Kirakara-Flutter-Engine'

# Optional full-process diagnostic with the same two Phase 1 order-dependent
# adapter controls preserved in one report.
.\engine\scripts\test_patched_windows_engine.ps1 `
  -WorkspaceRoot 'E:\Kirakara-Flutter-Engine' `
  -Suite adapter-isolated,full `
  -AllowKnownFullSuiteOrderFailures
```

`critical` covers the delayed task runner and next-frame callback paths that
must remain live. `compositor` covers the upstream Windows OpenGL/software
compositor, display/DPI and texture registrar fixtures. `adapter-isolated`
runs the two low-power-adapter cases in separate processes. `full` runs the
entire upstream binary and fails on every non-zero exit by default. On a
machine where the full process has already proven the exact two documented
adapter-order failures while both isolated cases pass, the diagnostic run may
explicitly use `-Suite adapter-isolated,full` together with
`-AllowKnownFullSuiteOrderFailures`; the script requires both controls in the
same report. The raw non-zero exit and test names remain in JSON and are never
silently discarded.

The real Stage integration baseline accepts debug and profile modes because
`flutter drive` cannot drive a Windows release build. After building release
with `build_windows_app.ps1`, use the bounded launch smoke instead:

```powershell
.\engine\scripts\smoke_windows_app.ps1 `
  -FlutterSdkRoot 'D:\Program Files\Flutter' `
  -Engine local `
  -WorkspaceRoot 'E:\Kirakara-Flutter-Engine' `
  -Mode release
```

The smoke verifies the selected DLL and ICU file before launch, waits for the
GUI input queue, and uses a bounded 100 ms startup probe because Flutter does
not show the top-level HWND until its first frame. This test-only probe is not
an application timer. It then checks the main window remains responsive,
requests a normal close, and writes a JSON report. A shutdown timeout fails by
default and kills only the exact child process it launched.
`-AllowForcedCleanup` is for explicitly documenting an already reproduced
shutdown defect; the forced cleanup remains visible in the report.

## Phase 2 synthetic DirectComposition probe

The synthetic backend is opt-in. An unset backend, `stock`, or
`external_texture` leaves the upstream render surface unchanged. The probe
requires the exact patched source and locked custom DLL, then builds a separate
Dart entry point and records counter gates:

```powershell
.\tool\windows_compositor\run_synthetic_compositor_probe.ps1 `
  -FlutterSdkRoot 'D:\Program Files\Flutter' `
  -WorkspaceRoot 'E:\Kirakara-Flutter-Engine' `
  -LocalEngine host_debug_kirakara_v3 `
  -TimeoutSeconds 45
```

After a successful build, a repeat can use `-SkipBuild`. The target display
must be awake and the window visible: Windows returns
`STATUS_GRAPHICS_PRESENT_OCCLUDED` from the compositor clock when the display
is off, and the probe deliberately reports that as a failed runtime gate rather
than hiding it with a timer or busy loop. The probe also performs one bounded
window contraction and restore, requiring two successful in-place swapchain
resizes while the top-level HWND and single DComp visual tree remain unchanged.
It also opens and closes the test overlay and independent Flutter page, proving
that both preserve the HWND, surface size and visual tree while Stage continues
to advance, then requires Flutter presents to return to quiescence. Each JSON
report records the current window DPI plus every monitor's bounds, DPI and scale
percentage, and the interactive footer displays the measured window scale. Use
`-KeepOpen` for the visual Alpha, page, resize, native IME and mixed-DPI
checklist in the Phase 2 report.

The Runner manifest must remain `PerMonitorV2`; a DPI-unaware process reports
virtualized monitor bounds and cannot validate this matrix. Startup converts the
historical 1600x900 physical target into monitor-relative logical dimensions, so
enabling real DPI does not enlarge the initial window while Flutter and DComp
still receive the actual scale. The runtime report also checks the target HWND's
awareness context directly; a manifest-only or 100%-only false positive fails.

Use `-ExpectedScalePercent 100|125|150|175|200` to bind a run to the
measured window DPI. Add `-RequireMixedDpi` for cross-monitor runs; it rejects
single-monitor and same-scale multi-monitor environments. When multiple
monitors are available, the harness automatically prefers a different-DPI
target, moves the same HWND there and back, and checks DPI transitions, restored
geometry, the single DComp tree and Stage progress. A single-monitor run records
that sample as explicitly skipped instead of treating it as a pass.

## Phase 3 real Show Stage probe

The real probe selects `composed`, loads two bounded Show fixtures, and validates
the NT-handle/keyed-mutex latest-frame path without changing the physical Stage
or Cast APIs:

The Engine consumer first probes `AcquireSync` with a zero timeout. If the
producer has already published the descriptor but cross-device GPU work is
still completing, only the dedicated consumer thread waits once for that
published key. Dropping that descriptor would strand the keyed mutex on the
consumer key and make every later non-blocking producer acquire fail. This is
not a polling loop and never blocks Show, Flutter platform/raster threads, the
physical Stage, or Cast.

```powershell
.\tool\windows_compositor\run_real_stage_compositor_probe.ps1 `
  -FlutterSdkRoot 'D:\Program Files\Flutter' `
  -WorkspaceRoot 'E:\Kirakara-Flutter-Engine' `
  -LocalEngine host_debug_kirakara_v3 `
  -TimeoutSeconds 90
```

It checks static Flutter isolation, a bounded platform-thread stall, in-place
resize, contain/cover geometry, Flutter overlays/pages, untitled and titled
program generations, pause/resume, replay, natural EOF, reload, detach and
reattach. The report rejects callback/schema errors, handle duplication or
resource-open failures, stale frames, failed HRESULTs and device removal. It
uses one duration-derived EOF wait and no recurring timer or active polling.

Preserve and test the compatibility backend independently with both the
official Engine and the patched Engine:

```powershell
.\tool\windows_compositor\run_windows_stage_texture_baseline.ps1 `
  -ShowRepository 'D:\仓库\Kirakara Show' `
  -FlutterExecutable 'D:\Program Files\Flutter\bin\flutter.bat' `
  -Mode debug `
  -Engine official

.\tool\windows_compositor\run_windows_stage_texture_baseline.ps1 `
  -ShowRepository 'D:\仓库\Kirakara Show' `
  -FlutterExecutable 'D:\Program Files\Flutter\bin\flutter.bat' `
  -Mode debug `
  -Engine local `
  -LocalVariant patched `
  -EngineWorkspaceRoot 'E:\Kirakara-Flutter-Engine'
```

The A/B runner explicitly sets `KIRAKARA_COMPOSITOR_BACKEND=external_texture`
for its child process and restores the caller's environment afterward. A
selected composed backend fails visibly on an ABI, synchronization or runtime
error; it does not silently use external texture to hide an implementation
defect. Full protocol, ownership and current evidence are recorded in
`docs/windows_compositor/phase3_real_show_stage.md`.

## Safety rules

- Never point `WorkspaceRoot` inside the App repository or at the installed
  Flutter SDK.
- Never patch `D:\Program Files\Flutter` or a compiled DLL.
- Keep stock and patched build configurations available together.
- Switch source variants only with `apply_patches.ps1`; it refuses to reverse a
  tree containing edits beyond the locked patchset.
- A revision, patch hash or artifact hash mismatch is a hard error. Do not
  continue by silently accepting a different binary.
- Proxy values are process-scoped inputs; they are not written to the lock or
  to application settings.
