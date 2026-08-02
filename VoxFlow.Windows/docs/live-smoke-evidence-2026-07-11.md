# Windows cloud live-smoke evidence — 2026-07-11

This evidence contains no credentials, request headers, prompts, transcripts,
or model responses. Credentials were supplied only through private process
environment variables and were removed with the test process. The committed
sample remains empty and CI keeps all live tests disabled by default.

## Environment

- Host: Windows 10 x64, build 19045
- Test runtime: .NET 10.0.9, x64
- Audio fixture: `TestResources/ASRSmoke/Audio/zh_short.wav`
- Fixture format: PCM S16LE, 16,000 Hz, mono
- Fixture SHA-256:
  `f62cc6cfaf9d087a64c8cf994a3c72118c5e46ed261c6ee12bf93c607cc059b8`
- Test enable gate: `VOXFLOW_LIVE_ENABLED=1`, set only for each explicit run

## Results

| Compatibility path | Result | Assertion |
| --- | --- | --- |
| Tencent Cloud realtime ASR | PASS | Non-empty authoritative final from the fixed WAV |
| Alibaba Cloud DashScope realtime ASR | PASS | Non-empty authoritative final from the fixed WAV |
| Volcengine realtime ASR | PASS | Non-empty authoritative final from the fixed WAV |
| OpenAI-compatible Tencent TokenHub stream | PASS | Non-empty SSE final and terminal completion |

The three ASR cases passed together (`3/3`) in an explicit local run. The
OpenAI-compatible case passed independently (`1/1`). Each test constructs only
the selected provider client, so an error cannot trigger another provider.
Offline tests separately cover provider-specific failure propagation, SSE
interruption fallback to raw ASR text, and the absence of automatic provider
fallback.

No live credential is read by `.github/workflows/windows-ci.yml`, and no
TokenHub base URL, key, model, or prompt is present in a product default.
