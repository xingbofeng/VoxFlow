# VoxFlow Windows licenses

VoxFlow is distributed under GPL-3.0-or-later. The complete project license is
available in the repository root `LICENSE` file and must be included in every
Windows installer.

## Native runtime sources

| Component | Source | License | Distribution rule |
| --- | --- | --- | --- |
| antirez/qwen-asr | https://github.com/antirez/qwen-asr | MIT | Pin an audited revision, preserve its copyright and MIT license, and record local patches in `native/qwen-asr/UPSTREAM.md`. |
| FFmpeg `n8.1.2-22-g94138f6973-20260710` | https://github.com/BtbN/FFmpeg-Builds/releases/tag/autobuild-2026-07-10-13-44 and https://github.com/FFmpeg/FFmpeg/commit/94138f6973 | LGPL-3.0-or-later build | Ship the reviewed `win64-lgpl-shared-8.1` executables and shared libraries together, preserve `LICENSE.txt`, publish the corresponding FFmpeg source, build configuration, file sizes, and SHA-256 values, and never replace the package with a GPL/nonfree variant or a PATH executable. |
| VoxFlow Agent sidecar | This repository, `agent-cli/` | MIT component within the GPL-3.0-or-later VoxFlow distribution | Preserve the crate's declared MIT terms and the project GPL license. Build only the locked `builtin-agent` feature for `x86_64-pc-windows-msvc` with static CRT; stage it at `runtime/agent/`, record source revision/size/SHA-256, and never discover a replacement through PATH. |
| Tesseract `5.5.2` | https://github.com/tesseract-ocr/tesseract/tree/5.5.2 | Apache-2.0 | Build only from the reviewed source on Windows x64/MSVC with vcpkg baseline `03e366fb91e38b9432ebd5f8cc79f7c8f55e96ab` and triplet `x64-windows-static`; preserve the 11,358-byte Apache license and stage only a hash-verified `runtime/ocr/` payload. |
| tessdata_fast `87416418657359cb625c412a48b6e1d6d41c29bd` | https://github.com/tesseract-ocr/tessdata_fast/tree/87416418657359cb625c412a48b6e1d6d41c29bd | Apache-2.0 | Ship only `eng`, `chi_sim`, `chi_tra`, `jpn`, and `kor`, each with the fixed size/SHA-256 in `TESSERACT_RUNTIME_MANIFEST.json`; do not locate additional system data or models through PATH. |

### Tesseract static native dependency inventory

The following libraries are the complete vcpkg runtime build closure linked
into the reviewed `tesseract.exe`. They do not add DLLs to the installation,
but their package-provided copyright and license notices are copied verbatim
to `runtime/ocr/licenses/` and hash-listed in
`TESSERACT_RUNTIME_MANIFEST.json`. Build-only vcpkg helper ports are not
shipped and are not part of this table. NASM 3.01 is downloaded from the
official NASM release archive with fixed size/SHA-256 and is used only as an
OpenSSL build tool; it is not included in the application package.

| vcpkg port | Version | Source | SPDX/license |
| --- | --- | --- | --- |
| bzip2 | `1.0.8#6` | https://sourceware.org/bzip2/ | bzip2-1.0.6 |
| curl | `8.21.0#1` | https://github.com/curl/curl | curl AND ISC AND BSD-3-Clause |
| giflib | `6.1.3` | https://sourceforge.net/projects/giflib/ | MIT |
| leptonica | `1.87.0` | https://github.com/DanBloomberg/leptonica | BSD-2-Clause |
| libarchive | `3.8.7` | https://github.com/libarchive/libarchive | BSD-2-Clause |
| libjpeg-turbo | `3.2.0` | https://github.com/libjpeg-turbo/libjpeg-turbo | BSD-3-Clause AND IJG |
| liblzma | `5.8.3` | https://github.com/tukaani-project/xz | 0BSD |
| libpng | `1.6.58` | https://github.com/pnggroup/libpng | libpng-2.0 |
| libwebp | `1.6.0#2` | https://github.com/webmproject/libwebp | BSD-3-Clause |
| lz4 | `1.10.0` | https://github.com/lz4/lz4 | BSD-2-Clause |
| openjpeg | `2.5.4` | https://github.com/uclouvain/openjpeg | BSD-2-Clause |
| openssl | `3.6.3` | https://github.com/openssl/openssl | Apache-2.0 |
| tiff | `4.7.2` | https://gitlab.com/libtiff/libtiff | libtiff |
| zlib | `1.3.2#1` | https://github.com/madler/zlib | Zlib |
| zstd | `1.5.7` | https://github.com/facebook/zstd | BSD-3-Clause (selected distribution option) |

The Tesseract executable itself remains Apache-2.0 and its complete license is
`runtime/ocr/LICENSE.txt`. The five tessdata files use the same Apache-2.0
license. The release gate requires the exact dependency names, versions,
source URLs, license expressions, notice paths, file sizes, and SHA-256 values;
an added, removed, or modified native input fails packaging.

The FFmpeg archive is
`ffmpeg-n8.1.2-22-g94138f6973-win64-lgpl-shared-8.1.zip`, GitHub asset
`472524907`, with SHA-256
`cd39114d50ad2d17d892571d896f67fbe8b25333958682430f095eeffbb58598`.
It is built for `x86_64-w64-mingw32` with `--enable-shared`,
`--disable-static`, `--disable-libx264`, `--disable-libx265`,
`--disable-libxvid`, and without `--enable-gpl` or `--enable-nonfree`.
The package reports GNU Lesser General Public License version 3. The exact
runtime inventory and build provenance are in `runtime/ffmpeg/`.

## Agent sidecar Cargo runtime inventory

The Windows sidecar dependency set below is the complete normal-dependency
closure selected by `Cargo.lock` for `x86_64-pc-windows-msvc`,
`--no-default-features --features builtin-agent`. Development dependencies and
the Unix-only full CLI are not shipped. Every entry comes from the checksummed
crates.io registry; its canonical source page is
`https://crates.io/crates/<crate>/<version>`. Where a crate offers a choice,
the distribution relies on the MIT or Apache-2.0 option. Unicode-3.0 remains
an additional required license where stated and is included in the installer.

<!-- cargo-runtime-inventory:start -->
| License expression | Locked runtime crates |
| --- | --- |
| (MIT OR Apache-2.0) AND Unicode-3.0 | `unicode-ident@1.0.24` |
| Apache-2.0 OR BSL-1.0 | `ryu@1.0.23` |
| Apache-2.0 OR MIT | `atomic-waker@1.1.2`, `idna_adapter@1.2.2`, `pin-project-lite@0.2.17`, `utf8_iter@1.0.4`, `zeroize@1.9.0` |
| Apache-2.0 | `sync_wrapper@1.0.2` |
| MIT OR Apache-2.0 | `anyhow@1.0.102`, `base64@0.22.1`, `bitflags@2.13.0`, `displaydoc@0.2.6`, `form_urlencoded@1.2.2`, `futures-channel@0.3.32`, `futures-core@0.3.32`, `futures-io@0.3.32`, `futures-sink@0.3.32`, `futures-task@0.3.32`, `futures-util@0.3.32`, `http@1.4.2`, `httparse@1.10.1`, `idna@1.1.0`, `ipnet@2.12.0`, `itoa@1.0.18`, `libc@0.2.186`, `log@0.4.32`, `native-tls@0.2.18`, `once_cell@1.21.4`, `percent-encoding@2.3.2`, `proc-macro2@1.0.106`, `quote@1.0.45`, `reqwest@0.12.28`, `rustls-pki-types@1.15.0`, `serde@1.0.228`, `serde_core@1.0.228`, `serde_derive@1.0.228`, `serde_json@1.0.150`, `smallvec@1.15.2`, `socket2@0.6.4`, `stable_deref_trait@1.2.1`, `syn@2.0.118`, `thiserror@2.0.18`, `thiserror-impl@2.0.18`, `url@2.5.8`, `windows-link@0.2.1`, `windows-sys@0.61.2` |
| MIT | `bytes@1.12.0`, `http-body@1.0.1`, `http-body-util@0.1.3`, `hyper@1.10.1`, `hyper-util@0.1.20`, `mio@1.2.1`, `schannel@0.1.29`, `slab@0.4.12`, `synstructure@0.13.2`, `tokio@1.52.3`, `tokio-native-tls@0.3.1`, `tower@0.5.3`, `tower-http@0.6.11`, `tower-layer@0.3.3`, `tower-service@0.3.3`, `tracing@0.1.44`, `tracing-core@0.1.36`, `try-lock@0.2.5`, `want@0.3.1`, `zmij@1.0.21` |
| MIT/Apache-2.0 | `hyper-tls@0.6.0`, `serde_urlencoded@0.7.1` |
| Unicode-3.0 | `icu_collections@2.2.0`, `icu_locale_core@2.2.0`, `icu_normalizer@2.2.0`, `icu_normalizer_data@2.2.0`, `icu_properties@2.2.0`, `icu_properties_data@2.2.0`, `icu_provider@2.2.0`, `litemap@0.8.2`, `potential_utf@0.1.5`, `tinystr@0.8.3`, `writeable@0.6.3`, `yoke@0.8.3`, `yoke-derive@0.8.2`, `zerofrom@0.1.8`, `zerofrom-derive@0.1.7`, `zerotrie@0.2.4`, `zerovec@0.11.6`, `zerovec-derive@0.11.3` |
| Unlicense OR MIT | `memchr@2.8.2` |
<!-- cargo-runtime-inventory:end -->

## Managed and installer dependencies

The Windows screenshot workbench dynamically links the unmodified NuGet DLLs
from ScreenCapture.NET commit `af9f75c63e54d057af4a158be4098058b50d700a`.
`ScreenCapture.NET`, `ScreenCapture.NET.DX11`, and HPPH are distributed under
LGPL-2.1-only. Their corresponding source is available from
https://github.com/DarthAffe/ScreenCapture.NET and the source links recorded in
their NuGet metadata. The Windows package keeps these assemblies as separate,
replaceable files and includes `licenses/LICENSE-LGPL-2.1-only.txt`; they must
not be merged, embedded into a single executable, or obfuscated in a way that
prevents replacement with a compatible build. Vortice and SharpGen runtime
assemblies used by the capture backend are distributed under MIT.

The table below is the complete restored NuGet graph, including build and test
tooling. `Runtime` means the package is resolved by at least one project under
`src/`; `Development/test` packages are not shipped in the application. The
inventory is checked against `dotnet list package --include-transitive --format
json` in CI, so an added, removed, or version-changed package must update this
file in the same change.

<!-- nuget-inventory:start -->
| Package | Version | SPDX/license | Scope | Source |
| --- | --- | --- | --- | --- |
| coverlet.collector | 6.0.4 | MIT | Development/test | https://www.nuget.org/packages/coverlet.collector/6.0.4 |
| HPPH | 1.0.0 | LGPL-2.1-only | Runtime | https://www.nuget.org/packages/HPPH/1.0.0 |
| Microsoft.CodeCoverage | 17.14.1 | MIT | Development/test | https://www.nuget.org/packages/Microsoft.CodeCoverage/17.14.1 |
| Microsoft.Data.Sqlite | 10.0.9 | MIT | Runtime | https://www.nuget.org/packages/Microsoft.Data.Sqlite/10.0.9 |
| Microsoft.Data.Sqlite.Core | 10.0.9 | MIT | Runtime | https://www.nuget.org/packages/Microsoft.Data.Sqlite.Core/10.0.9 |
| Microsoft.NET.Test.Sdk | 17.14.1 | MIT | Development/test | https://www.nuget.org/packages/Microsoft.NET.Test.Sdk/17.14.1 |
| Microsoft.TestPlatform.ObjectModel | 17.14.1 | MIT | Development/test | https://www.nuget.org/packages/Microsoft.TestPlatform.ObjectModel/17.14.1 |
| Microsoft.TestPlatform.TestHost | 17.14.1 | MIT | Development/test | https://www.nuget.org/packages/Microsoft.TestPlatform.TestHost/17.14.1 |
| NAudio.Core | 2.3.0 | MIT | Runtime | https://www.nuget.org/packages/NAudio.Core/2.3.0 |
| NAudio.Wasapi | 2.3.0 | MIT | Runtime | https://www.nuget.org/packages/NAudio.Wasapi/2.3.0 |
| Newtonsoft.Json | 13.0.3 | MIT | Development/test | https://www.nuget.org/packages/Newtonsoft.Json/13.0.3 |
| ScreenCapture.NET | 3.0.0 | LGPL-2.1-only | Runtime | https://www.nuget.org/packages/ScreenCapture.NET/3.0.0 |
| ScreenCapture.NET.DX11 | 3.0.0 | LGPL-2.1-only | Runtime | https://www.nuget.org/packages/ScreenCapture.NET.DX11/3.0.0 |
| SharpGen.Runtime | 2.1.2-beta | MIT | Runtime | https://www.nuget.org/packages/SharpGen.Runtime/2.1.2-beta |
| SharpGen.Runtime.COM | 2.1.2-beta | MIT | Runtime | https://www.nuget.org/packages/SharpGen.Runtime.COM/2.1.2-beta |
| SourceGear.sqlite3 | 3.50.4.5 | blessing | Runtime | https://www.nuget.org/packages/SourceGear.sqlite3/3.50.4.5 |
| SQLitePCLRaw.bundle_e_sqlite3 | 3.0.3 | Apache-2.0 | Runtime | https://www.nuget.org/packages/SQLitePCLRaw.bundle_e_sqlite3/3.0.3 |
| SQLitePCLRaw.config.e_sqlite3 | 3.0.3 | Apache-2.0 | Runtime | https://www.nuget.org/packages/SQLitePCLRaw.config.e_sqlite3/3.0.3 |
| SQLitePCLRaw.core | 3.0.3 | Apache-2.0 | Runtime | https://www.nuget.org/packages/SQLitePCLRaw.core/3.0.3 |
| SQLitePCLRaw.provider.e_sqlite3 | 3.0.3 | Apache-2.0 | Runtime | https://www.nuget.org/packages/SQLitePCLRaw.provider.e_sqlite3/3.0.3 |
| System.Security.Cryptography.ProtectedData | 10.0.9 | MIT | Runtime | https://www.nuget.org/packages/System.Security.Cryptography.ProtectedData/10.0.9 |
| System.Speech | 10.0.0 | MIT | Runtime | https://www.nuget.org/packages/System.Speech/10.0.0 |
| Vortice.Direct3D11 | 3.5.0 | MIT | Runtime | https://www.nuget.org/packages/Vortice.Direct3D11/3.5.0 |
| Vortice.DirectX | 3.5.0 | MIT | Runtime | https://www.nuget.org/packages/Vortice.DirectX/3.5.0 |
| Vortice.DXGI | 3.5.0 | MIT | Runtime | https://www.nuget.org/packages/Vortice.DXGI/3.5.0 |
| Vortice.Mathematics | 1.7.8 | MIT | Runtime | https://www.nuget.org/packages/Vortice.Mathematics/1.7.8 |
| xunit | 2.9.3 | Apache-2.0 | Development/test | https://www.nuget.org/packages/xunit/2.9.3 |
| xunit.abstractions | 2.0.3 | Apache-2.0 | Development/test | https://www.nuget.org/packages/xunit.abstractions/2.0.3 |
| xunit.analyzers | 1.18.0 | Apache-2.0 | Development/test | https://www.nuget.org/packages/xunit.analyzers/1.18.0 |
| xunit.assert | 2.9.3 | Apache-2.0 | Development/test | https://www.nuget.org/packages/xunit.assert/2.9.3 |
| xunit.core | 2.9.3 | Apache-2.0 | Development/test | https://www.nuget.org/packages/xunit.core/2.9.3 |
| xunit.extensibility.core | 2.9.3 | Apache-2.0 | Development/test | https://www.nuget.org/packages/xunit.extensibility.core/2.9.3 |
| xunit.extensibility.execution | 2.9.3 | Apache-2.0 | Development/test | https://www.nuget.org/packages/xunit.extensibility.execution/2.9.3 |
| xunit.runner.visualstudio | 3.1.4 | Apache-2.0 | Development/test | https://www.nuget.org/packages/xunit.runner.visualstudio/3.1.4 |
<!-- nuget-inventory:end -->

The resolved native SQLite payload comes from `SourceGear.sqlite3 3.50.4.5`;
the obsolete `SQLitePCLRaw.lib.e_sqlite3 2.1.11` package is intentionally not
part of the graph. `SQLitePCLRaw.bundle_e_sqlite3 3.0.3` is a direct pin so a
future `Microsoft.Data.Sqlite` transitive constraint cannot silently restore
that older native library.

The five xUnit.net v2 package/version pairs currently reported as `Legacy` are
development/test-only. The security gate allows only their exact IDs and
versions through 2026-12-31, then fails closed; any production deprecation or
any other test deprecation remains blocking. A coordinated xUnit v3 migration
must remove this temporary exception before its expiry.

License references used by this inventory:

- MIT: https://opensource.org/license/mit
- LGPL-2.1-only: https://www.gnu.org/licenses/old-licenses/lgpl-2.1.html
- Apache-2.0: https://www.apache.org/licenses/LICENSE-2.0.txt
- SQLite blessing/public-domain notice: https://sqlite.org/copyright.html

Copyright and attribution notices from the resolved package metadata:

- Microsoft-authored packages: Copyright Microsoft Corporation. All rights
  reserved; distributed under MIT as listed above.
- SQLitePCLRaw and SourceGear.sqlite3 packaging: Copyright 2014-2026
  SourceGear, LLC (individual package end years vary); the embedded SQLite
  library is public domain under the SQLite blessing.
- Newtonsoft.Json: Copyright James Newton-King.
- NAudio: Copyright Mark Heath and contributors; the WASAPI and core packages
  are distributed under MIT.
- ScreenCapture.NET and ScreenCapture.NET.DX11: Copyright Darth Affe and
  contributors; distributed under LGPL-2.1-only. HPPH is also distributed
  under LGPL-2.1-only as declared by its restored package metadata.
- Vortice and SharpGen runtime packages: Copyright Amer Koleci and respective
  contributors; distributed under MIT.
- xUnit.net packages: Copyright .NET Foundation; `xunit.abstractions` credits
  James Newkirk and Brad Wilson.
- coverlet.collector: coverlet contributors (NuGet author: tonerdo).

Before packaging, copy the package-provided copyright notices and required
license texts for every `Runtime` row into the installer license directory.
The source-controlled inventory and package-contained license files are the
release inputs; generated binaries are not a substitute for either.
