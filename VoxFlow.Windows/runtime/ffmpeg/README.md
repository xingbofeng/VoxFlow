# FFmpeg runtime provenance

VoxFlow Windows locks FFmpeg to the immutable NuGet package
`DevEnvy.FFmpeg.Binaries.LGPL` version `8.0.1.4`:

- package: `devenvy.ffmpeg.binaries.lgpl.8.0.1.4.nupkg`
- FFmpeg version: `8.0.1`
- target: Windows x64
- license declared by the package: LGPL-2.1-or-later
- package mode: shared libraries, not static linking

Upstream URLs:

- https://www.nuget.org/packages/DevEnvy.FFmpeg.Binaries.LGPL/8.0.1.4
- https://ffmpeg.org/legal.html

The reviewed configuration enables shared libraries and disables static
libraries. It does not contain `--enable-gpl` or `--enable-nonfree`; GPL-only
codec integrations including libx264, libx265, and libxvid are disabled.
`FFMPEG_RUNTIME_MANIFEST.json` is the fail-closed file inventory used at
startup and by release checks. `ffplay.exe` is intentionally excluded because
VoxFlow uses NAudio for playback.

Release packaging must include the package's unmodified
`THIRD_PARTY_NOTICES.md` and all nine manifested runtime files. The application
may only resolve this directory; it must not search `PATH` or download a
replacement.
