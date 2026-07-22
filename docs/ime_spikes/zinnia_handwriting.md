# Zinnia Handwriting Spike

Phase 5 adds the Flutter handwriting pad and routes recognition through
`ZinniaHandwritingEngine`. Windows now uses the bundled native Zinnia runtime
first and reports runner/model failures in the candidate bar when the channel
or packaged models are unavailable.

Windows packaging:

```text
windows runner
  -> statically links the configuration-matched kirakara_zinnia.lib
  -> installs ime/zinnia/windows/models/handwriting-ja.model
  -> installs ime/zinnia/windows/models/handwriting-zh_CN.model
```

No Zinnia DLL or `runtime` directory is installed in the application bundle.
The runner reads both
model files with Unicode-safe Windows paths, keeps their bytes alive for the
recognizer lifetime, and opens them through Zinnia's in-memory API. This keeps
handwriting available when the application path contains non-ASCII text.

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

The UI owns drawing, clear, undo, and candidate commit. Each completed stroke
triggers recognition with the current stroke set, so candidates update
incrementally while the user writes. Selecting a candidate commits that
character, clears the handwriting canvas, and prepares the pad for the next
character.

The native bridge only receives stroke points and returns candidates, so
candidate commit stays shared with Rime and Mozc.

The bridge does not query the catalog, inspect page results, or return song
metadata. Handwriting only produces input candidates; local search consumes the
committed text later.
