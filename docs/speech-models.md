# Speech Models

VoxFlow supports Apple Speech out of the box, local ASR providers for offline workflows, and cloud providers for users who prefer hosted recognition. The app labels local versus cloud, streaming support, language coverage, and readiness in the Models UI.

## Local And System Providers

Local providers keep audio on the Mac, except for Apple Speech behavior governed by macOS system services.

| Provider / Model | Status | Streaming | Runtime Route | Recommended Use |
| --- | --- | --- | --- | --- |
| Apple Speech | Supported | Yes | Apple Speech / `SFSpeechRecognizer` | Start immediately without downloading a model |
| Qwen3-ASR 0.6B | Supported | Partial + final | speech-swift `Qwen3ASR` / MLX 4bit | Default local dictation route with balanced size and speed |
| Qwen3-ASR 1.7B | Supported | Partial + final | speech-swift `Qwen3ASR` / MLX 8bit | Higher-accuracy local dictation when memory allows |
| Whisper Turbo / Large V3 | Supported | No | WhisperKit `.mlmodelc` | High-quality full-recording transcription after capture ends |
| FunASR | Supported | Segment confirmation | Sherpa-ONNX | Local Chinese fallback route, not CoreML |
| SenseVoice | Supported | Short utterance / non-streaming path | FluidAudio / CoreML | Local multilingual short-utterance transcription |
| Paraformer Large zh | Supported | Segment confirmation | FluidAudio / CoreML int8 | Local Chinese transcription |
| NVIDIA Nemotron 0.6B | Supported | Yes | speech-swift `NemotronStreamingASR` / CoreML | Local multilingual streaming candidate |
| Parakeet Streaming | Supported | Yes | speech-swift `ParakeetStreamingASR` / CoreML | Low-latency English and European-language dictation |
| Omnilingual ASR | Supported | No | speech-swift `OmnilingualASR` / CoreML | Broad-language offline transcription and experimental workflows |

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
- Use **Whisper** for high-quality file or recording transcription where real-time feedback is less important.
- Use **Tencent Cloud** or **Alibaba Cloud** when you need cloud streaming.
- Use **Groq** when you want hosted final transcription without local model downloads.
