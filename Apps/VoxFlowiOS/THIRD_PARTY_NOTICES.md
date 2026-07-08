# Third-Party Notices for Mashangxie iOS

This file records license attribution for open-source code copied or planned for
direct source-copy integration under `Apps/VoxFlowiOS/`.

## Dictus iOS

- Upstream: Dictus iOS
- Source commit: `7264b1d892adfddd1d9cf3a5f7c4debb37b00019`
- License: MIT
- Copyright: Copyright (c) 2026 PIVI Solutions
- Use in this repository: copied source for the iOS Keyboard Extension UI,
  shared App Group / Darwin notification layer, keyboard state machine, logging,
  design components, and keyboard vendored support code.

MIT License

Copyright (c) 2026 PIVI Solutions

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

## Hamster

- Upstream: Hamster
- Source commit: `65693706d01fc6c19ed6071968e542b0a2ef3f36`
- License: MIT
- Copyright: Copyright (c) 2025 xiao.fu
- Use in this repository: Chinese input implementation references and copied
  source for RimeKit/RimeContext-related structures, Chinese 26-key,
  Chinese 9-key/T9, schema deployment, and related Chinese input behavior.

MIT License

Copyright (c) 2025 xiao.fu

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

## Rime Native Dependency Bundle

- Source: `https://github.com/amorphobia/LibrimeKit/releases/download/v0.1.0/Frameworks.tgz`
- Local path: `Apps/VoxFlowiOS/ChineseInput/Frameworks/`
- Use in this repository: native xcframework dependencies for the
  RimeKit-backed Chinese input runtime.

The bundle contains static xcframeworks for:

- `librime` — BSD-3-Clause
- `boost_atomic`, `boost_filesystem`, `boost_regex`, `boost_system` — Boost
  Software License
- `libglog` — BSD-3-Clause
- `libleveldb` — BSD-3-Clause
- `libmarisa` — BSD-style license
- `libopencc` — Apache-2.0
- `libyaml-cpp` — MIT

Before distributing a build that links these native artifacts, re-audit the
embedded binary licenses and include the full license texts required by each
library in the final app notices.

## Rime Ice Schema Data

- Upstream: `iDvel/rime-ice`
- Source revision: `846e5fcae56f0e3f4dcd8570319ffaf377e15471`
- Source files: `rime_ice.schema.yaml`, `rime_ice.dict.yaml`,
  `t9.schema.yaml`, dependency schemas, dictionaries, Lua helpers, and OpenCC
  resources copied into `Apps/VoxFlowiOS/ChineseInput/Resources/Schemas/`.
- License: GNU General Public License v3.0
- Use in this repository: bundled Chinese 26-key `rime_ice` scheme and 9-key/T9
  scheme following Hamster's default Rime route.

The bundled schema resources are copied from upstream Rime Ice without converting
the dictionaries into project-generated pinyin or T9 dictionaries. The 9-key
route uses upstream `t9.schema.yaml`, which inherits the `rime_ice` dictionary
and applies Rime speller algebra for T9 digit input.

GNU General Public License v3.0 text is available from:
`https://www.gnu.org/licenses/gpl-3.0.txt`.
