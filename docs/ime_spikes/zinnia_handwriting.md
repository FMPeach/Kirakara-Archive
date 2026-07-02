# Zinnia Handwriting Spike

Phase 5 adds the Flutter handwriting pad and routes recognition through
`ZinniaHandwritingEngine`. Windows now uses the bundled native Zinnia runtime
first and falls back to `MockHandwritingImeEngine` only when the runner channel
or packaged models are unavailable.

Windows packaging:

```text
windows runner
  -> statically links kirakara_zinnia
  -> installs ime/zinnia/windows/models/handwriting-ja.model
  -> installs ime/zinnia/windows/models/handwriting-zh_CN.model
```

Flutter bridge:

```text
MethodChannel: kirakara/ime
zinnia.activate
zinnia.deactivate
zinnia.recognize
zinnia.clear
```

`zinnia.recognize` receives stroke points grouped by stroke. The Windows bridge
normalizes them into a 1000x1000 Zinnia character, classifies against Japanese
and Chinese models, deduplicates candidates, sorts by score, and returns
`NativeImeCandidate` maps to Flutter.

The UI owns drawing, clear, undo, and recognize actions. The native bridge only
receives stroke points and returns candidates, so candidate commit stays shared
with Rime and Mozc.

The bridge does not query the catalog, inspect page results, or return song
metadata. Handwriting only produces input candidates; local search consumes the
committed text later.
