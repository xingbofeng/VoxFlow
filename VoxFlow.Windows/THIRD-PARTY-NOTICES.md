# VoxFlow Windows licenses

VoxFlow is distributed under GPL-3.0-or-later. The complete project license is
available in the repository root `LICENSE` file and must be included in every
Windows installer.

## Native runtime sources

| Component | Source | License | Distribution rule |
| --- | --- | --- | --- |
| antirez/qwen-asr | https://github.com/antirez/qwen-asr | MIT | Pin an audited revision, preserve its copyright and MIT license, and record local patches in `native/qwen-asr/UPSTREAM.md`. |
| FFmpeg `n8.1.2-22-g94138f6973-20260710` | https://github.com/BtbN/FFmpeg-Builds/releases/tag/autobuild-2026-07-10-13-44 and https://github.com/FFmpeg/FFmpeg/commit/94138f6973 | LGPL-3.0-or-later build | Ship the reviewed `win64-lgpl-shared-8.1` executables and shared libraries together, preserve `LICENSE.txt`, publish the corresponding FFmpeg source, build configuration, file sizes, and SHA-256 values, and never replace the package with a GPL/nonfree variant or a PATH executable. |

The FFmpeg archive is
`ffmpeg-n8.1.2-22-g94138f6973-win64-lgpl-shared-8.1.zip`, GitHub asset
`472524907`, with SHA-256
`cd39114d50ad2d17d892571d896f67fbe8b25333958682430f095eeffbb58598`.
It is built for `x86_64-w64-mingw32` with `--enable-shared`,
`--disable-static`, `--disable-libx264`, `--disable-libx265`,
`--disable-libxvid`, and without `--enable-gpl` or `--enable-nonfree`.
The package reports GNU Lesser General Public License version 3. The exact
runtime inventory and build provenance are in `runtime/ffmpeg/`.

## Managed and installer dependencies

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
| Microsoft.CodeCoverage | 17.14.1 | MIT | Development/test | https://www.nuget.org/packages/Microsoft.CodeCoverage/17.14.1 |
| Microsoft.Data.Sqlite | 10.0.9 | MIT | Runtime | https://www.nuget.org/packages/Microsoft.Data.Sqlite/10.0.9 |
| Microsoft.Data.Sqlite.Core | 10.0.9 | MIT | Runtime | https://www.nuget.org/packages/Microsoft.Data.Sqlite.Core/10.0.9 |
| Microsoft.NET.Test.Sdk | 17.14.1 | MIT | Development/test | https://www.nuget.org/packages/Microsoft.NET.Test.Sdk/17.14.1 |
| Microsoft.TestPlatform.ObjectModel | 17.14.1 | MIT | Development/test | https://www.nuget.org/packages/Microsoft.TestPlatform.ObjectModel/17.14.1 |
| Microsoft.TestPlatform.TestHost | 17.14.1 | MIT | Development/test | https://www.nuget.org/packages/Microsoft.TestPlatform.TestHost/17.14.1 |
| NAudio.Core | 2.3.0 | MIT | Runtime | https://www.nuget.org/packages/NAudio.Core/2.3.0 |
| NAudio.Wasapi | 2.3.0 | MIT | Runtime | https://www.nuget.org/packages/NAudio.Wasapi/2.3.0 |
| Newtonsoft.Json | 13.0.3 | MIT | Development/test | https://www.nuget.org/packages/Newtonsoft.Json/13.0.3 |
| SourceGear.sqlite3 | 3.50.4.5 | blessing | Runtime | https://www.nuget.org/packages/SourceGear.sqlite3/3.50.4.5 |
| SQLitePCLRaw.bundle_e_sqlite3 | 3.0.3 | Apache-2.0 | Runtime | https://www.nuget.org/packages/SQLitePCLRaw.bundle_e_sqlite3/3.0.3 |
| SQLitePCLRaw.config.e_sqlite3 | 3.0.3 | Apache-2.0 | Runtime | https://www.nuget.org/packages/SQLitePCLRaw.config.e_sqlite3/3.0.3 |
| SQLitePCLRaw.core | 3.0.3 | Apache-2.0 | Runtime | https://www.nuget.org/packages/SQLitePCLRaw.core/3.0.3 |
| SQLitePCLRaw.provider.e_sqlite3 | 3.0.3 | Apache-2.0 | Runtime | https://www.nuget.org/packages/SQLitePCLRaw.provider.e_sqlite3/3.0.3 |
| System.Security.Cryptography.ProtectedData | 10.0.9 | MIT | Runtime | https://www.nuget.org/packages/System.Security.Cryptography.ProtectedData/10.0.9 |
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
- xUnit.net packages: Copyright .NET Foundation; `xunit.abstractions` credits
  James Newkirk and Brad Wilson.
- coverlet.collector: coverlet contributors (NuGet author: tonerdo).

Before packaging, copy the package-provided copyright notices and required
license texts for every `Runtime` row into the installer license directory.
The source-controlled inventory and package-contained license files are the
release inputs; generated binaries are not a substitute for either.
