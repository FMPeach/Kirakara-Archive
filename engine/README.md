# Kirakara Windows Flutter Engine

This directory contains only the reproducibility contract for the custom
Windows Flutter Engine. Engine source, `out/`, DLLs, import libraries, symbols
and downloaded toolchains must remain in an external workspace or a versioned
release artifact. They must not be committed to the App repository.

Phase 1 is deliberately stock: the checkout is pinned to the Engine revision
used by Flutter 3.44.4 and `patchset.patches` is empty. A successful Phase 1
build therefore proves the local toolchain before any Kirakara behavior change
is introduced.

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
      └─ host_release\
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

For Phase 1, applying patches is a no-op that also proves the source tree is
clean:

```powershell
.\engine\scripts\apply_patches.ps1 `
  -WorkspaceRoot 'E:\Kirakara-Flutter-Engine'

.\engine\scripts\build_windows_engine.ps1 `
  -WorkspaceRoot 'E:\Kirakara-Flutter-Engine' `
  -Mode debug,profile,release `
  -VisualStudioPath 'D:\Program Files\Microsoft Visual Studio\Community\2026'
```

Builds use the upstream `windows/host_debug`, `windows/host_profile` and
`windows/host_release` local configurations with RBE disabled. The script never
copies products into this repository. It sets `VCToolsVersion` for the build
process, and verification rejects a generated `toolchain.ninja` or PE linker
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
  -Mode debug,profile,release `
  -RequireLockedHashes

# Local stock Engine
.\engine\scripts\build_windows_app.ps1 `
  -FlutterSdkRoot 'D:\Program Files\Flutter' `
  -Engine local `
  -WorkspaceRoot 'E:\Kirakara-Flutter-Engine' `
  -Mode profile

# Official cached Engine; no local-engine flags are passed.
.\engine\scripts\build_windows_app.ps1 `
  -FlutterSdkRoot 'D:\Program Files\Flutter' `
  -Engine official `
  -Mode profile
```

The local and official modes use the same pinned Flutter SDK. This is the
documented one-operation A/B switch. The verifier writes its report below the
ignored `build/diagnostics/engine` directory. Once Phase 1 products have been
generated, their sizes and SHA-256 values are copied into the lock and
`-RequireLockedHashes` becomes the release gate.

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
  -Mode debug,profile,release `
  -ReportPath '.\build\diagnostics\engine\candidate-artifacts.json' `
  -CaptureArtifactHashes
```

That diagnostic mode still enforces revisions, a clean stock tree, `args.gn`,
MSVC selection, PE linker version and official/local exports. It reports every
artifact difference, emits a warning and never edits `engine.lock.json`.
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

## Safety rules

- Never point `WorkspaceRoot` inside the App repository or at the installed
  Flutter SDK.
- Never patch `D:\Program Files\Flutter` or a compiled DLL.
- Keep stock and patched build configurations available together.
- A revision, patch hash or artifact hash mismatch is a hard error. Do not
  continue by silently accepting a different binary.
- Proxy values are process-scoped inputs; they are not written to the lock or
  to application settings.
