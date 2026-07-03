# Third-Party IME Runtime Status

Kirakara-App keeps third-party IME source snapshots outside the Flutter product
repository. The product repository should only carry runtime binaries, runtime
data/models, and required license or notice files.

External source archive on this workstation:

```text
D:\Kirakara-ThirdParty-IME-Sources
  upstream-sources/
  kirakara-bridge-sources/
```

Current Windows engine status:

| Engine | Role | Runtime status | Product repo payload |
| --- | --- | --- | --- |
| Rime | Pinyin | Active through the Windows runner MethodChannel and bundled `rime.dll` | `third_party/ime/rime/windows/rime.dll`, schemas, dictionaries, OpenCC data |
| Mozc | Japanese romaji | Active through bundled helper process `kirakara_mozc_bridge.exe` | `third_party/ime/mozc/windows/runtime/kirakara_mozc_bridge.exe`, Mozc notice |
| Zinnia | Handwriting | Active through the Windows runner MethodChannel and bundled handwriting models | `third_party/ime/zinnia/windows/runtime/kirakara_zinnia.lib` for building, `third_party/ime/zinnia/windows/models/*.model`, Zinnia and tomoe notices |

Interaction boundaries:

- IME engines only produce input composition, candidates, and committed text.
- IME engines do not query song catalogs, categories, singers, rankings, or
  local search results.
- Catalog/search consumes committed text after the user selects a candidate or
  commits raw input.

Cleanup policy:

- Keep compiled/runtime artifacts in this repository.
- Keep license and notice files in this repository.
- Do not keep upstream IME source trees or local bridge source snapshots here.
- Rime Weasel UI resources such as `preview/*.png` and `weasel.yaml` are not
  needed because Kirakara renders its own touch keyboard and candidate UI.
- Build-only artifacts such as `kirakara_zinnia.lib` may live in this
  repository but should be excluded from the installed runtime package.
