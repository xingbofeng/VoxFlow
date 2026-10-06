# Speech Models

VoxFlow supports Apple Speech out of the box, local ASR providers for offline workflows, and cloud providers for users who prefer hosted recognition. The app labels local versus cloud, streaming support, language coverage, and readiness in the Models UI.

“Offline” here means recognition without a cloud service, not necessarily final-only decoding: X-ASR runs locally and incrementally.

## Local And System Providers

Local providers keep audio on the Mac, except for Apple Speech behavior governed by macOS system services.

The matrix below describes the macOS app. A macOS provider entry does not imply that the same model is available on Windows or iOS. “Supported” means the runtime is integrated; readiness still depends on the installed model and hardware checks.

| Provider / Model | Status | Streaming | Runtime Route | Recommended Use |
| --- | --- | --- | --- | --- |
| Apple Speech | Supported | Yes | Apple Speech / `SFSpeechRecognizer` | Start immediately without downloading a model |
| Qwen3-ASR 0.6B | Supported | Partial + final | speech-swift `Qwen3ASR` / MLX 4bit | Default local dictation route with balanced size and speed |
| Qwen3-ASR 1.7B | Supported | Partial + final | speech-swift `Qwen3ASR` / MLX 8bit | Higher-accuracy local dictation when memory allows |
| Confucius4-R2T2 | Supported | Stable prefix + revisable tail | `VoxFlowR2T2Core` / MLX 8bit | Local Chinese/English dictation with live feedback on Apple Silicon |
| FireRedASR2-AED | Supported | Rolling re-decode previews; final from full re-decode | Vendored sherpa-onnx / AED int8 | Chinese-focused recognition and dialect coverage; allow time for final decoding |
| Whisper Turbo / Large V3 | Supported | No | WhisperKit `.mlmodelc` | High-quality full-recording transcription after capture ends |
| FunASR | Supported | Segment confirmation | Sherpa-ONNX | Local Chinese fallback route, not CoreML |
| SenseVoice | Supported | Short utterance / non-streaming path | FluidAudio / CoreML | Local multilingual short-utterance transcription |
| Paraformer Large zh | Supported | Segment confirmation | FluidAudio / CoreML int8 | Local Chinese transcription |
| NVIDIA Nemotron 0.6B | Supported | Yes | speech-swift `NemotronStreamingASR` / CoreML | Local multilingual streaming candidate |
| Parakeet Streaming | Supported | Yes | speech-swift `ParakeetStreamingASR` / CoreML | Low-latency English and European-language dictation |
| Omnilingual ASR | Supported | No | speech-swift `OmnilingualASR` / CoreML | Broad-language offline transcription and experimental workflows |
| X-ASR-zh-en | Integrated in development source; acceptance in progress | Native incremental decoding | Existing sherpa-onnx 1.13.3 Online C API | Apple Silicon Chinese/English streaming; 8 GiB memory gate |

### Recent Local Model Additions

- **Confucius4-R2T2** requires Apple Silicon, macOS 15+, and at least 16 GB of memory; 24 GB is recommended. Its fixed 8bit download occupies about 2.31 GiB. Committed text only grows; the unconfirmed tail may change before finalization. This is a separate provider from the existing Qwen3-ASR entries.
- **FireRedASR2-AED** requires macOS 15+ and at least 16 GB of memory. The installed AED int8 files occupy about 1.15 GiB (1.24 GB); the download archive and extracted files also need staging space. Live preview re-decodes accumulated audio after at least one second of new input when no preview decode is running. Final text comes from a separate full-recording decode, with silence-aware segments for recordings longer than 50 seconds. This is an offline model with live previews, rather than a native streaming decoder.
- Both integrated providers use the existing **local model live preview** setting, require user-initiated model downloads, and leave the default provider unchanged. R2T2 accepts vocabulary through prompt context; FireRedASR currently has no hotword delivery API. Prompt context is distinct from native decoder hotword boosting. Runtime integration does not mean that every device or microphone workflow has completed live acceptance testing.
- **X-ASR-zh-en** is now implemented in development source: Apple Silicon only, macOS 15+, and an 8 GiB memory gate. The fixed 480ms model contains four verified files totalling 614,596,718 bytes (about 586 MiB). It uses the existing sherpa-onnx 1.13.3, caches the recognizer, and flushes the final tail with one second of zero padding. Initial native tests produced the first text after roughly 1.2–1.6 seconds of audio; the chunk size is not a latency guarantee. Full device/microphone/UI acceptance remains separate from the passed native tests, and this addition is not part of the previously prepared v1.17.0 release notes.

Download these models under **Settings → Models**. Integrity checks, atomic installation, and a real inference canary must complete before selection. X-ASR has passed a five-minute recording replay through the App audio pipeline, not physical microphone/UI acceptance or lower-memory-device testing. Its first version does not advertise file-workbench transcription, hotwords, or automatic segment submission. FireRedASR's live-preview toggle currently filters display without stopping preview computation; that limitation is recorded here, not shipped as a fix.

Model ownership and licensing are recorded in [Resource ownership](resource-ownership.md).

## Cloud Providers

Cloud providers send recorded audio to the selected service. Credentials are stored in the local credentials file.

| Cloud Provider | Status | Streaming | Default Model / API | Configuration |
| --- | --- | --- | --- | --- |
| Groq | Supported | No | `whisper-large-v3-turbo` audio transcription | API key and model |
| Tencent Cloud | Supported | Yes | Realtime Speech Recognition WebSocket, `16k_zh` | AppID, SecretId, SecretKey |
| Alibaba Cloud | Supported | Yes | DashScope WebSocket, `fun-asr-realtime` | Bailian API key |
| Volcengine Cloud | Planned | Planned | Doubao streaming ASR | To be determined |
| Mistral Voxtral | Not yet supported | To be determined | Voxtral speech capability | None |
| AssemblyAI | Not yet supported | To be determined | AssemblyAI Transcription | None |
| ElevenLabs Scribe | Not yet supported | To be determined | ElevenLabs Scribe | None |

## Selection Semantics

VoxFlow only persists a selected provider after it is selectable. If a local model is missing or a cloud credential is not configured, selecting that provider is rejected instead of silently persisting a provider that will fall back at runtime.

Older persisted settings can still fall back to Apple Speech when the selected provider becomes unavailable, such as after deleting a local model directory.

## Choosing A Provider

- Start with **Apple Speech** if you want the quickest setup.
- Use **Qwen3-ASR 0.6B** for local everyday dictation.
- Use **Qwen3-ASR 1.7B** when accuracy matters more than model size.
- Use **Confucius4-R2T2** when you want local Chinese/English dictation with live feedback and your Apple Silicon Mac meets its memory requirements.
- Try **FireRedASR2-AED** for Chinese-focused dictation or dialects when a heavier model and a separate final decode fit your workflow.
- Use **Whisper** for high-quality file or recording transcription where real-time feedback is less important.
- Use **Tencent Cloud** or **Alibaba Cloud** when you need cloud streaming.
- Use **Groq** when you want hosted final transcription without local model downloads.
