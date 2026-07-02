# Zinnia Handwriting Spike

Phase 5 adds the Flutter handwriting pad and routes recognition through
`ZinniaHandwritingEngine`. The engine tries a native Zinnia bridge first and
falls back to `MockHandwritingImeEngine` until the DLL and model package exist.

Expected Windows artifact:

```text
kirakara_zinnia.dll
```

Planned ABI shape:

```text
kirakara_zinnia_create_session(model_path) -> session handle
kirakara_zinnia_destroy_session(handle)
kirakara_zinnia_recognize_json_utf8(handle, strokes_json) -> json utf8
```

`strokes_json` should contain normalized pointer coordinates grouped by stroke.
The response maps to `NativeImeCandidate` and then into `CandidateBar`.

The UI owns drawing, clear, undo, and recognize actions. The native bridge only
receives stroke points and returns candidates, so candidate commit stays shared
with Rime and Mozc.
