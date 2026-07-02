# Rime Bridge Spike

Phase 3 keeps the Flutter UI on the generic `ImeEngine` surface and inserts a
`RimeImeEngine` for pinyin. The engine tries a native bridge first and falls
back to `MockPinyinImeEngine` while no DLL is configured.

Expected Windows artifact:

```text
kirakara_rime.dll
```

Planned ABI shape:

```text
kirakara_rime_create_session() -> session handle
kirakara_rime_destroy_session(handle)
kirakara_rime_select_schema(handle, "luna_pinyin")
kirakara_rime_compose_utf8(handle, raw_input, page_index) -> json utf8
kirakara_rime_clear(handle)
```

The JSON payload should map to `NativeImeResult`:

```json
{
  "rawInput": "lv",
  "preedit": "lv",
  "pageIndex": 0,
  "hasPreviousPage": false,
  "hasNextPage": false,
  "candidates": [
    { "text": "绿", "annotation": "lv", "score": 1.0 }
  ]
}
```

The first real spike only needs to prove `lv` and `lü` handling, candidate
paging, and candidate commit. UI code should not change when the bridge becomes
available.
