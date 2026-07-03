# Rime Bridge Spike

Phase 3 keeps the Flutter UI on the generic `ImeEngine` surface and inserts a
`RimeImeEngine` for pinyin. Windows now routes Rime calls through the runner
`kirakara/ime` MethodChannel and the bundled `rime.dll`; the mock engine is only
a development fallback when the native bridge fails.

Bundled Windows runtime:

```text
ime/
  rime/
    windows/
      rime.dll
      data/
```

Flutter bridge:

```text
MethodChannel: kirakara/ime
rime.activate
rime.deactivate
rime.compose
rime.clear
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

The runner uses the `luna_pinyin_simp` schema for the first pinyin path. Rime
only returns input candidates; local catalog/search handles song matching after
candidate commit.
