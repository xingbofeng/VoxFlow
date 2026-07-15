# FFmpeg runtime provenance

VoxFlow Windows locks FFmpeg to the BtbN release
`autobuild-2026-07-10-13-44`, asset `472524907`:

- package: `ffmpeg-n8.1.2-22-g94138f6973-win64-lgpl-shared-8.1.zip`
- FFmpeg version: `n8.1.2-22-g94138f6973-20260710`
- FFmpeg source revision: `94138f6973`
- target: `x86_64-w64-mingw32`
- license reported by the package: LGPL version 3
- package mode: shared libraries, not static linking

Upstream URLs:

- https://github.com/BtbN/FFmpeg-Builds/releases/tag/autobuild-2026-07-10-13-44
- https://github.com/FFmpeg/FFmpeg/commit/94138f6973
- https://ffmpeg.org/legal.html

The reviewed configuration enables shared libraries and disables static
libraries. It does not contain `--enable-gpl` or `--enable-nonfree`; GPL-only
codec integrations including libx264, libx265, and libxvid are disabled.
`FFMPEG_RUNTIME_MANIFEST.json` is the fail-closed file inventory used at
startup and by release checks. `ffplay.exe` is intentionally excluded because
VoxFlow uses NAudio for playback.

Release packaging must include the package's unmodified `LICENSE.txt`, the
corresponding FFmpeg source archive and build configuration link, and all nine
manifested runtime files. The application may only resolve this directory; it
must not search `PATH` or download a replacement.
