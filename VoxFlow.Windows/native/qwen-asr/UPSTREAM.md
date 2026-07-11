# qwen-asr upstream and Windows validation record

## Result

The pinned `antirez/qwen-asr` revision builds and runs on Windows x64 after
applying the checked-in, source-auditable Win32 portability overlay. The build
uses MSVC `/MT /W4 /WX`, produces an AMD64 PE, imports only `KERNEL32.dll`, and
transcribes the repository's fixed WAV through the real `--stdin --stream`
path with exit code 0 and non-empty UTF-8 output.

`MODEL_PROVENANCE.json` is now `publishable: true`: the runtime build,
dependency audit, fixed-WAV inference, model lifecycle, and installer
integration gates have all been implemented and reviewed. The immutable file
records the two official Windows model variants consumed by the product
catalog; changing any revision, byte count, hash, or runtime identity requires
a new audit.

## Repository

### Revision

- Repository: https://github.com/antirez/qwen-asr
- Full revision: `b00b789b17051aea61e9717458171100662318a4`
- Commit: https://github.com/antirez/qwen-asr/commit/b00b789b17051aea61e9717458171100662318a4
- Commit author date: `2026-02-15T19:40:32+01:00`
- Commit subject: `streaming: restore rollback stream path and sync docs/help`
- Retrieved source archive:
  https://github.com/antirez/qwen-asr/archive/b00b789b17051aea61e9717458171100662318a4.tar.gz
- Source archive size: `15,567,284` bytes
- Source archive SHA-256:
  `00dca18f0a1b251635c8f712836f641f4b0304cb6eb4859456911b707f38ea0b`

The build verifier rejects a checkout at any other revision or with tracked
modifications. It materializes the exact commit with `git archive`, then
applies the repository-owned overlay to that disposable copy. The upstream
checkout therefore stays clean and its identity remains independently
verifiable.

## License

### Model format and provenance

- Runtime license: MIT
- Preserved notice: `LICENSE.upstream`
- Preserved notice SHA-256:
  `663e51edcd9a3a8f858018ce6924ad2895a24c269c26c39ad75325bcd0f7e5bc`
- Upstream notice:
  https://github.com/antirez/qwen-asr/blob/b00b789b17051aea61e9717458171100662318a4/LICENSE
- Official model license: Apache-2.0

The pinned runtime reads the official Qwen BF16 safetensors format plus
`config.json`, `generation_config.json`, `vocab.json`, and `merges.txt`. The
1.7B model also uses `model.safetensors.index.json` and two safetensors shards.
Exact immutable URLs, revisions, file sizes, and SHA-256 values live in
`MODEL_PROVENANCE.json`:

- `qwen3-asr-0.6b` / `Qwen 0.6B`:
  `Qwen/Qwen3-ASR-0.6B@5eb144179a02acc5e5ba31e748d22b0cf3e303b0`
- `qwen3-asr-1.7b` / `Qwen 1.7B`:
  `Qwen/Qwen3-ASR-1.7B@7278e1e70fe206f11671096ffdd38061171dd6e5`

Mutable `resolve/main` model URLs are not used. The Windows records do not
reuse macOS model artifacts. A future installer must carry both the runtime
MIT notice and the model Apache-2.0 notice.

## Build parameters and audited Windows build

Validation host:

- Windows: `Microsoft Windows 10.0.19045.6466` x64
- Visual Studio Build Tools: `17.14.35`
- Compiler: Microsoft C/C++ `19.44.35228` for x64
- Linker: `14.44.35228.0`

This host proves the source and overlay on Windows 10. It does not replace the
later release acceptance run on a clean Windows 10 1809 VM.

The reproducible build entry point is:

```powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass `
  -File .\VoxFlow.Windows\native\qwen-asr\verify-upstream-msvc.ps1 `
  -SourceRoot <clean-checkout-at-b00b789> `
  -OutputRoot <empty-output-directory>
```

The production executable is compiled with:

```text
/nologo /utf-8 /std:c11 /O2 /fp:fast /arch:AVX2 /W4 /WX /MT
/D_CRT_SECURE_NO_WARNINGS /D__AVX2__=1 /D__FMA__=1
/link /INCREMENTAL:NO
```

The overlay contract test is also compiled with `/MT /W4 /WX` and run before
the runtime build. No external BLAS is linked, so this proof exercises the
pinned source's generic C fallback with AVX2/FMA kernels. The resulting binary
therefore requires an AVX2/FMA-capable x64 CPU.

PE inspection confirmed `IMAGE_FILE_MACHINE_AMD64`. `dumpbin /DEPENDENTS`
reported exactly:

```text
KERNEL32.dll
```

There are no imported Python, CUDA, MLX, pthread compatibility, `VCRUNTIME`, or
`MSVCP` DLLs. `/MT` statically links the MSVC runtime; no helper process,
server, WSL environment, or managed language runtime is part of this path.

## Local patches and portability overlay

The overlay is under `windows-port/` and is compiled from source with the
pinned runtime:

- `include/pthread.h` and `src/windows_compat.c`: mutexes, conditions, and
  threads implemented with SRW locks, condition variables, and
  `_beginthreadex`.
- `include/sys/mman.h`: read-only file mapping with
  `CreateFileMappingW`/`MapViewOfFile`, including files larger than 4 GiB.
- `include/dirent.h`: UTF-8 directory enumeration with
  `FindFirstFileW`/`FindNextFileW`.
- `include/sys/time.h` and `include/unistd.h`: precise wall-clock time and CPU
  discovery using Win32 APIs.
- `include/windows-msvc.h`: guarded MSVC compiler/POSIX shims.
- `tests/windows_compat_test.c`: runtime contracts for synchronization,
  mapping, directory enumeration, timing, CPU discovery, and compiler shims.
- `patches/0001-msvc-c11-cleanups.patch`: four small changes applied to the
  disposable pinned-source copy.

The cleanup patch SHA-256 is
`519fd8434a4e5f9ffd4a067686c552905eca0a5e1387ac2f467ea9007f2965a8`.
It switches stdin to binary mode on Windows (preventing byte `0x1A` from being
treated as text EOF), replaces one GCC statement expression with portable C11,
marks one parameter as used for `/WX`, and removes unreachable placeholder
code rejected by MSVC. It does not change model math, weights, or the public
upstream context API.

## Validation evidence: fixed-WAV inference

The official immutable 0.6B model was downloaded from the URLs in
`MODEL_PROVENANCE.json`; all five files matched their recorded sizes and
SHA-256 values before inference.

- Fixture: `TestResources/ASRSmoke/Audio/zh_short.wav`
- Format: PCM S16LE, 16,000 Hz, mono
- Size: `116,832` bytes
- SHA-256:
  `f62cc6cfaf9d087a64c8cf994a3c72118c5e46ed261c6ee12bf93c607cc059b8`
- Runtime mode: `--stdin --stream -t 6`
- Process exit: `0`
- Transcript: valid, non-empty UTF-8; `53` bytes
- Transcript SHA-256:
  `24e9e3a872d050055f1113f0250a3201807da81206edbeae279631955001a8d2`
- Runtime diagnostics: `9` text tokens, `108,034 ms` inference for `3.5 s`
  audio (`0.03x` realtime); observed wall time `110 s`

The transcript hash and byte count prove deterministic non-empty output
without storing spoken content in the audit record. The generic, no-BLAS build
is functionally correct but far below realtime on this host; it is not a
latency acceptance result and must not be presented as one.

Re-run the model/hash/inference proof with:

```powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass `
  -File .\VoxFlow.Windows\native\qwen-asr\verify-fixed-wav.ps1 `
  -ExecutablePath <build-output>\qwen_asr.exe `
  -ModelRoot <verified-qwen3-asr-0.6b-directory> `
  -WavPath .\TestResources\ASRSmoke\Audio\zh_short.wav `
  -OutputRoot <empty-evidence-directory>
```

The verifier refuses stale output, re-hashes every pinned 0.6B model file and
the WAV, requires process exit 0, validates UTF-8 and non-empty transcript
content, and checks the runtime diagnostics. Its console result exposes only
the transcript byte count/hash and elapsed time.

## Interface boundary

The pinned CLI documents both file and live stdin streaming:

```text
qwen_asr -d <model-dir> -i <audio.wav> --stream
qwen_asr -d <model-dir> --stdin --stream
```

The source-level context API provides model load, token callbacks,
whole-buffer transcription, and streaming transcription. It does not itself
provide VoxFlow's versioned opaque start/push/poll/finish/cancel/error ABI;
that remains the responsibility of the separate native bridge layer.
