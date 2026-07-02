# Mozc Bridge Spike

Phase 4 keeps Japanese romaji input behind the same `ImeEngine` interface as
English, Rime, and handwriting. `MozcImeEngine` tries a native bridge first and
falls back to `MockJapaneseImeEngine` until the Mozc spike DLL exists.

Expected Windows artifact:

```text
kirakara_mozc.dll
```

Planned ABI shape:

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

The bridge returns `NativeImeResult`, so Flutter UI code stays unchanged when
the native bridge replaces the mock fallback.
