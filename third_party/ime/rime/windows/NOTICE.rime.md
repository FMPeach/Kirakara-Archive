# Rime Runtime Notice

This directory bundles Rime runtime artifacts for Kirakara-App's app-owned
pinyin input path.

Included runtime pieces:

- `rime.dll`: Rime engine runtime, from the librime project.
- `data/`: Rime schemas, dictionaries, and OpenCC conversion data used by the
  bundled runtime.

Upstream references:

- librime: https://github.com/rime/librime
- Rime prelude schemas: https://github.com/rime/rime-prelude
- Rime luna pinyin schemas/data: https://github.com/rime/rime-luna-pinyin

License notes:

- librime is distributed under a BSD-style license by RIME Developers.
- Rime schema/data packages may carry LGPL-3.0 terms, depending on the package.
- Kirakara-App keeps source snapshots outside this product repository at
  `D:\Kirakara-ThirdParty-IME-Sources`.

This notice is a project bookkeeping aid and is not legal advice. Review the
upstream license files again before public binary distribution.
