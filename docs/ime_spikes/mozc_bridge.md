# Mozc Bridge Spike

Phase 4 keeps Japanese romaji input behind the same `ImeEngine` interface as
English, Rime, and handwriting. `MozcImeEngine` now probes an app-owned Windows
helper first and reports helper failures in the candidate bar instead of
generating fixed mock candidates when that helper is
missing or fails during development.

Hard boundary:

- Do not require users to install Google Japanese Input, Mozc, or any system
  IME.
- Do not register a Windows TSF input method.
- Do not use Mozc candidates as catalog search results.
- The bridge returns only input candidates; Search / Catalog handles song
  matching after commit.

Bundled Windows runtime:

```text
ime/
  mozc/
    windows/
      runtime/
        kirakara_mozc_bridge.exe
      COPYING.mozc
```

Flutter calls the helper as a short-lived app-owned process:

```text
kirakara_mozc_bridge.exe compose <raw_input> <page_index> <page_size>
kirakara_mozc_bridge.exe clear
kirakara_mozc_bridge.exe activate
kirakara_mozc_bridge.exe deactivate
```

Each command writes one UTF-8 JSON object to stdout. `compose` maps directly to
`NativeImeResult`:

```json
{
  "ok": true,
  "rawInput": "nihongo",
  "preedit": "にほんご",
  "pageIndex": 0,
  "hasPreviousPage": false,
  "hasNextPage": true,
  "candidates": [
    {"text": "日本語"},
    {"text": "ニホンゴ"},
    {"text": "にほんご"}
  ]
}
```

Verified inputs:

- `nihongo` returns `日本語`, `ニホンゴ`, and `にほんご`.
- `zankokunatenshi` returns `残酷な天使` as the first full-preedit candidate.
- `ai` returns candidates such as `愛`, `アイ`, and `あい`.

Rebuild notes:

1. Use the clean Mozc source tree at `D:\Kirakara-Mozc-src\src`.
2. Copy
   `D:\Kirakara-ThirdParty-IME-Sources\kirakara-bridge-sources\mozc\windows\source\kirakara_mozc_bridge.cc`
   into `src/session/kirakara_mozc_bridge.cc`.
3. Append the target from
   `D:\Kirakara-ThirdParty-IME-Sources\kirakara-bridge-sources\mozc\windows\source\BUILD.bazel`
   to `src/session/BUILD.bazel`. Mozc's private target visibility requires the
   bridge to live in the upstream `//session` package.
4. Build with Bazel 9.0.2 and Mozc's Windows deps:

```powershell
$bazel = Join-Path $env:TEMP 'kirakara-tools\bazel-9.0.2.exe'
$env:PATH = 'D:\Kirakara-Mozc-src\src\third_party\msys64\usr\bin;D:\Kirakara-Mozc-src\src\third_party\ninja;' + $env:PATH
$env:BAZEL_LLVM = 'D:\Kirakara-Mozc-src\src\third_party\llvm'
$env:BAZEL_SH = 'D:\Kirakara-Mozc-src\src\third_party\msys64\usr\bin\bash.exe'
& $bazel --nowindows_enable_symlinks build --config oss_windows --config release_build --noenable_runfiles //session:kirakara_mozc_bridge
```

5. Copy
   `D:\Kirakara-Mozc-src\src\bazel-bin\session\kirakara_mozc_bridge.exe` to
   `third_party/ime/mozc/windows/runtime/kirakara_mozc_bridge.exe`.

The helper is intentionally Windows-only for this prototype. Android can keep
the same Dart `ImeEngine` contract and replace the process bridge with a native
library or platform channel later.
