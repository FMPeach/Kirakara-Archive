# Kirakara Windows Flutter Engine

This directory contains the reproducibility contract for the custom Windows
Flutter Engine. The normal App workflow is repository-local: source, `out/`,
DLLs, symbols and downloaded toolchains live below the ignored `.kfe/`
directory and must never be committed or added to a source package. Phase 7
release artifacts can be produced either from the preserved external workspace
or from the separately reviewed repository-local Release candidate described
later in this document.

The root `builds` entries preserve the completely stock Phase 1 artifacts for
Flutter 3.44.4. `patchset` separately locks the ordered Phase 2/3 compositor and
Phase 6 clipboard patches, their resulting Git tree, additional public export
and custom debug/profile/release artifacts.
Switching variants never edits the installed Flutter SDK and never removes the
other variant's `out/` directory.

## App developer workflow

From the repository root, use the checked-in wrapper instead of a bare
`flutter` command for Windows work:

```powershell
.\flutterw pub get
.\flutterw run -d windows
.\flutterw run -d windows --profile
.\flutterw build windows
```

Any of these commands can be the first command after cloning. `pub get` and a
default Windows run prepare debug; an explicit profile run prepares profile;
and a Windows build without a mode prepares release. Modes are lazy and are
not built until requested. The wrapper selects the locked Flutter SDK, prepares
and validates the required Engine, injects the three local-Engine arguments,
then invokes the original Flutter command. `flutterw.cmd` provides the same
entry for `cmd.exe` and IDE tasks.

The wrapper requires Git, PowerShell 7 (`pwsh`; Windows PowerShell 5 is
explicitly rejected), the Visual Studio/MSVC/ATL
identity and Windows SDK pinned in `engine.lock.json`. Reserve at least 64 GiB
of free space before the initial bootstrap. Download and compilation time
depends heavily on the network, CPU and storage and can range from tens of
minutes to several hours; the scripts display actual child-process progress
and do not invent an ETA.

If a matching ordinary Flutter SDK is already on `PATH`, it is validated and
used read-only. Otherwise the unmodified locked SDK is cloned into `.kfe/sdk`.
The installed SDK is never patched, and custom DLLs are never copied into its
cache. A proxy is opt-in and process-scoped:

```powershell
$env:KIRAKARA_ENGINE_PROXY = 'http://127.0.0.1:7890'
.\flutterw pub get
Remove-Item Env:\KIRAKARA_ENGINE_PROXY
```

All Kirakara-specific state is contained in this ignored layout:

```text
.kfe/
├─ sdk/          # fallback, unmodified locked Flutter SDK
├─ depot_tools/  # locked revision
├─ engine/       # locked source, gclient and CIPD content
├─ out/          # lazy debug/profile/release outputs
├─ pub-cache/    # project-only Dart packages
├─ cache/        # project-only CIPD/vpython/depot_tools caches
├─ tmp/          # child-process TEMP/TMP
├─ logs/         # verification and ABI reports
├─ locks/        # cross-process bootstrap ownership
└─ state/        # mode-specific fingerprints and ready stamps
```

The second invocation reuses a mode only after rechecking its fingerprint,
source tree, toolchain, GN arguments, exports, ABI and artifacts. Offline reuse
therefore works only when the matching ready stamp and every referenced source,
cache and output file are already present. A partial download, failed build or
missing stamp is never passed to Flutter.

Development fingerprints cover the build-relevant lock contract but exclude
exact reviewed output hashes under `projectBootstrap.releaseCandidate` and the
historical `builds[*].artifacts` lists. Relocking a distribution candidate
therefore does not rebuild debug/profile/release Engines. Changing a revision,
source tree, patch, GN target/argument, ABI, toolchain identity or build script
still invalidates the corresponding ready stamp.

Interrupted managed Git checkouts are resumed only when their origin matches
the lock and they have no tracked edits. A clone that stopped before creating
Git metadata is removed only at its exact managed `.kfe` path and fetched
again. Wrong origins and tracked changes fail explicitly. Old `.kfe/logs`
files are bounded by the lock while reports referenced by current ready stamps
remain protected.

The repository and `.kfe` workspace may live under a non-ASCII Windows path;
no junction, mapped drive or global alias is required. The bootstrap builds
locked, patched GN and Ninja binaries from source and applies narrowly scoped
Unicode fixes to vpython virtualenv, Engine `shader_archiver`, and the nested
Dart `gen_snapshot` repository. Exact revisions, patch hashes, stock/patched
trees and upstream test counts are part of `engine.lock.json`. Main-repository
and nested-dependency patches use the same exact reverse/apply gates.

After the profile Engine is ready, the focused path regression can be repeated
without rebuilding it:

```powershell
.\engine\scripts\test_project_engine_unicode_paths.ps1
```

It runs `shader_archiver` and `gen_snapshot` inside a real Chinese `.kfe/tmp`
directory, verifies their outputs, and removes only that bounded probe folder.

The pinned stock Flutter 3.44.4 tool has a separate non-ASCII-path bug in
`flutter analyze`: it writes the LSP `Content-Length` using Dart character
count rather than UTF-8 byte count, so the analysis server receives truncated
JSON. Direct `dart analyze` is the current non-mutating workaround. The wrapper
does not patch either official SDK or hide the repository behind an alias; the
three Windows bootstrap entry points above are unaffected.

The fallback SDK boundary has a repeatable diagnostic:

```powershell
.\engine\scripts\test_flutterw_local_sdk_fallback.ps1
```

It temporarily hides every Flutter command visible on `PATH`, removes the
process-only explicit SDK override, and requires `flutterw` to select
`.kfe/sdk`. Its default `pub get` also enters the debug Engine state machine.
If that SDK does not exist, the command performs the real locked bootstrap;
otherwise it proves offline-style reuse without another clone or precache. It
also checks all three official Windows DLLs, revisions, tracked state,
process/user/machine environment, global Git configuration and every external
Flutter checkout that was visible before isolation. Pass
`-WrapperArguments @('--version')` for the SDK-only form.

Use these maintenance commands when needed:

```powershell
.\flutterw engine status
.\flutterw engine doctor
.\flutterw engine prepare debug
.\flutterw engine clean debug
.\flutterw engine purge
```

`engine clean` deletes only the selected `.kfe/out` mode and its ready stamp;
`engine purge` deletes only this repository's `.kfe/`. Both share the bootstrap
lock. Ordinary `flutterw clean` remains Flutter's App clean and preserves the
Engine workspace. Do not manually delete `.kfe/` while a wrapper process is
running.

The repository's double-click Windows build/run launchers under `tool/` resolve
the current clone from their own location and call `flutterw.cmd`. They do not
pin a drive path or prepend a machine-specific Flutter SDK. The direct Debug
executable launcher performs an incremental wrapper build before launch so it
cannot silently run a stale Engine bundle.

The checked-in `engine/vscode` task and launch examples call `flutterw` as the
same state-machine entry. The repository ignores local `.vscode/` preferences,
so merge the examples into that directory as described by their README. The
launch entries run Flutter in a terminal so the wrapper stays authoritative;
use the separate Dart attach entry when an IDE debugger is needed.

A bare global `flutter` command is intentionally not intercepted. Flutter has
no per-project pre-command hook covering `pub get`, `run` and `build`, and a
PATH alias would leak Kirakara's Engine into neighboring repositories. Bare
Flutter remains appropriate for non-Windows comparison work, while Kirakara
Windows commands must use `flutterw`.

## External Engine developer and release workflow

The lower-level Phase 1-7 scripts remain available for Engine development,
stock/custom A/B comparison and reproducible release-candidate packaging. They
use an explicitly supplied external workspace:

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
      ├─ host_debug_kirakara_v4\
      ├─ host_profile_kirakara_v4\
      └─ host_release_kirakara_v4\
```

No absolute host path is stored in `engine.lock.json`. The example uses E: only
because it has enough free space and keeps the checkout path short.

## Fetch and synchronize

Run from a normal PowerShell first. On Windows, upstream documents an
administrator requirement for some `gclient` setups; elevate only if the
command reports the corresponding permission failure.

```powershell
Set-Location 'D:\path\to\Kirakara-App'
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
  -Mode debug,profile,release `
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
`windows/host_release` configurations; the current patch stack locks matching
`host_debug_kirakara_v4`, `host_profile_kirakara_v4` and
`host_release_kirakara_v4` outputs. Profile and release explicitly build both
`gen_snapshot` and `flutter_patched_sdk`; an incomplete AOT toolchain is a hard
failure. Both variants disable RBE and never copy Engine products into this
repository. Verification rejects a generated `toolchain.ninja` or PE linker
version that does not use the locked 14.34 toolset.

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
  -Mode debug,profile,release `
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
  -Mode debug,profile,release

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

`clipboard` covers upstream behavior plus bounded contention, size and teardown
cases. `critical` covers the delayed task runner and next-frame callback paths
that must remain live. `compositor` covers the upstream Windows OpenGL/software
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
refreshes the process window cache, requests a normal close against the current
HWND, and writes a JSON report including the shutdown wait. The refresh matters
because the HWND can change after an earlier timed `WaitForExit`. A shutdown
timeout fails by default and kills only the exact child process it launched.
`-AllowForcedCleanup` is for explicitly documenting an already reproduced
shutdown defect; the forced cleanup remains visible in the report.

Verify that stock DLLs remain stock and every custom build rejects a mismatched
ABI before testing the exact locked metadata:

```powershell
.\engine\scripts\test_engine_abi_gate.ps1 `
  -FlutterSdkRoot 'D:\Program Files\Flutter' `
  -WorkspaceRoot 'E:\Kirakara-Flutter-Engine'
```

This probes debug/profile/release without creating a Flutter view. It requires
the official DLLs to omit the custom export, requires a wrong ABI and a wrong
API struct size to return the explicit version-mismatch result, and requires
the exact ABI, patchset version/revision, Engine revision and function table to
match the lock.

After a locked custom Release App build, create and smoke-test the distributable
candidates:

```powershell
.\engine\scripts\package_windows_release.ps1 `
  -FlutterSdkRoot 'D:\Program Files\Flutter' `
  -WorkspaceRoot 'E:\Kirakara-Flutter-Engine' `
  -ShowHostDll 'D:\仓库\Kirakara Show\build\bin\libshow_host.dll'
```

The ignored `build/releases` directory receives deterministic Portable,
per-user installer, patch-source and Engine-artifact ZIPs plus a release index
with SHA-256 values. The Engine archive contains the exact reviewed DLL, import
library, PDB, ICU, AOT tools and patched Dart SDK files for publication as a
Release asset; it must not be committed to Git or copied into the runtime ZIP.
The patch-source archive also carries the Windows compositor/clipboard capture,
fixture and probe tools referenced by the phase documents; generated media and
diagnostic outputs remain excluded.
Runtime smoke reports live in a `diagnostics/` child of the selected
output directory and the index records relative paths, so independent or
repeat builds using `-OutputDirectory` do not collide with an earlier run or
leak a builder-local absolute path. Runtime selection maps CMake's last
Debug/Profile/Release install
manifest to configuration-independent Release paths, includes the immutable
`data/` and `ime/` runtime trees, and permits only known top-level binary/JSON
types; an unclassified file fails packaging. This stays correct regardless of
which mode was built last. Settings, databases, session state and logs are
excluded. The default gate extracts and smokes the Portable package, verifies
every installer payload hash, installs without UAC to an isolated directory,
smokes that installation and exercises its guarded uninstaller.
`-SkipRuntimeSmoke` is only for a deterministic rebuild comparison, not release
acceptance.

`-ShowHostDll` is mandatory. Before any staging directory is created, the
packager loads that DLL and requires the versioned Stage Visual export, wrong
ABI/structure rejection, ABI 1, all four capabilities, protocol
`nt-keyed-latest-v1`, zero reserved fields, every function pointer and the D3D
device-binding export. The selected file must exactly match the Release bundle;
its hash and protocol metadata are written to both manifests. The tracked
`windows/runner/libshow_host.dll` intentionally remains the legacy
external-texture compatibility DLL and fails this composed-release gate.

The installer candidate is intentionally unsigned until the owner supplies a
production signing identity. The repository also needs an owner-selected
project-wide distribution license before a candidate can be called a final
public release. The scripts do not create a substitute self-signed production
identity or modify the system trust store.

## Phase 2 synthetic DirectComposition probe

The synthetic backend is opt-in. An unset backend, `stock`, or
`external_texture` leaves the upstream render surface unchanged. The probe
requires the exact patched source and locked custom DLL, then builds a separate
Dart entry point and records counter gates:

```powershell
.\tool\windows_compositor\run_synthetic_compositor_probe.ps1 `
  -FlutterSdkRoot 'D:\Program Files\Flutter' `
  -WorkspaceRoot 'E:\Kirakara-Flutter-Engine' `
  -LocalEngine host_debug_kirakara_v4 `
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
  -LocalEngine host_debug_kirakara_v4 `
  -ShowHostDll 'D:\仓库\Kirakara Show\build\bin\libshow_host.dll' `
  -TimeoutSeconds 90
```

It checks static Flutter isolation, a bounded platform-thread stall, in-place
resize, contain/cover geometry, Flutter overlays/pages, untitled and titled
program generations, pause/resume, replay, natural EOF, reload, detach and
reattach. The report rejects callback/schema errors, handle duplication or
resource-open failures, stale frames, failed HRESULTs and device removal. It
uses one duration-derived EOF wait and no recurring timer or active polling.

To add both video-master EOF mismatch directions, generate temporary media and
pass its root explicitly:

```powershell
$eofRoot = '.\build\diagnostics\eof-mismatch-fixtures'
.\tool\windows_compositor\make_eof_mismatch_fixtures.ps1 `
  -OutputDirectory $eofRoot
.\tool\windows_compositor\run_real_stage_compositor_probe.ps1 `
  -FlutterSdkRoot 'D:\Program Files\Flutter' `
  -WorkspaceRoot '.\.kfe' `
  -ShowHostDll 'D:\path\to\Kirakara Show\build\bin\libshow_host.dll' `
  -EofMismatchFixtureRoot $eofRoot `
  -LifecycleProbe `
  -ExitWhileActive
```

The generated media is never committed. The probe verifies that auxiliary
audio EOF does not stop a longer video-master program, that shorter video EOF
does stop a program with longer audio, and that an ordinary program can be
loaded afterward. All waits are finite and derived from probed media duration.

The Show input is resolved from the explicit parameter, the process-only
`KIRAKARA_SHOW_HOST_DLL` build variable, or a sibling `Kirakara Show` checkout,
in that order. The same ABI gate used for release packaging runs before build;
the resolved path is passed to CMake only for that child build and the caller's
environment is restored. With no override, CMake forcibly returns to the
tracked compatibility DLL instead of retaining a previous machine path in its
cache. Dart runtime loading always uses the DLL installed beside the App EXE.

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

## Phase 6 clipboard reliability probe

The clipboard patch is the second, separately removable Engine patch. It keeps
`SystemChannels.platform` and Flutter's standard `Clipboard` API intact. Only
`OpenClipboard` returning `ERROR_ACCESS_DENIED` is retried, using a temporary
message-window timer with a 250 ms overall deadline; there is no platform-thread
sleep, clipboard listener, startup read, history, persistence, upload, or text
logging.

Run the stock behavior gate first, then the contention gate against the exact
locked v4 Engine:

```powershell
.\tool\windows_clipboard\run_windows_clipboard_baseline.ps1 `
  -FlutterExecutable 'D:\Program Files\Flutter\bin\flutter.bat'

.\tool\windows_clipboard\run_windows_clipboard_contention_probe.ps1 `
  -FlutterSdkRoot 'D:\Program Files\Flutter' `
  -WorkspaceRoot 'E:\Kirakara-Flutter-Engine' `
  -LocalEngine host_debug_kirakara_v4
```

Both probes temporarily replace the system clipboard and can restore only its
prior plain-text representation. The custom probe uses a separate bounded test
process to hold `OpenClipboard`; its sleep is test scaffolding and never runs on
Flutter's platform thread. Engine unit tests cover transient get/set retries,
deadline exhaustion, no-text and oversized-text responses, and teardown while
a retry is pending.

## Safety rules

- Never point `WorkspaceRoot` inside the App repository or at the installed
  Flutter SDK.
- Never patch `D:\Program Files\Flutter` or a compiled DLL.
- Keep stock and patched build configurations available together.
- Switch source variants only with `apply_patches.ps1`; it refuses to reverse a
  tree containing edits beyond the locked patchset.
- A revision, patch hash, ready-stamp artifact hash, or reviewed release-candidate
  artifact hash mismatch is a hard error. A fresh development build may differ
  from the Phase 7 release lock because Windows PE/PDB outputs are not
  bit-for-bit reproducible; it must capture a new verification report and ready
  stamp, pass the ABI/export/source/toolchain gates, and must never silently
  relock `engine.lock.json`.
- Proxy values are process-scoped inputs; they are not written to the lock or
  to application settings.
