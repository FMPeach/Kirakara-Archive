# Mozc Bridge Spike

Phase 4 keeps Japanese romaji input behind the same `ImeEngine` interface as
English, Rime, and handwriting. `MozcImeEngine` tries a native bridge first and
falls back to `MockJapaneseImeEngine` until an app-owned Mozc runtime exists.

Hard boundary:

- Do not require users to install Google Japanese Input, Mozc, or any system
  IME.
- Do not register a Windows TSF input method.
- Do not use Mozc candidates as catalog search results.
- The bridge returns only input candidates; Search / Catalog handles song
  matching after commit.

Preferred Windows artifact shape:

```text
Kirakara app-owned runtime
  -> either a native library wrapping Mozc session/converter
  -> or a packaged mozc_server.exe plus app-owned IPC client
```

Desired bridge shape:

```text
kirakara_mozc_create_session() -> session handle
kirakara_mozc_destroy_session(handle)
kirakara_mozc_compose_utf8(handle, raw_input, page_index) -> json utf8
kirakara_mozc_clear(handle)
```

The first independent native spike should verify:

- session lifecycle
- romaji input such as `zankokunatenshi`
- candidate list paging
- candidate commit
- no dependency on the Windows system Japanese IME
- no dependency on any user-installed third-party IME

The bridge returns `NativeImeResult`, so Flutter UI code stays unchanged when
the native bridge replaces the mock fallback.

Current blocker:

- Mozc requires a reproducible native build chain before it can become the
  default runtime.
- A previous Bazel 9.0.2 download was corrupt; redo the download cleanly before
  attempting the Mozc build again.
- Until that build is verified, the app must not pretend Mozc is integrated.
