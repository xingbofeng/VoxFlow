# 语音模型

码上写支持开箱可用的 Apple Speech、本地离线 ASR Provider，以及可选云端 Provider。模型页会明确标注本地/云端、流式能力、语言覆盖和可用状态。

## 本地和系统 Provider

本地 Provider 会把音频留在 Mac 上处理；Apple Speech 的行为由 macOS 系统服务决定。

| Provider / 模型 | 状态 | 流式能力 | 运行路线 | 推荐用途 |
| --- | --- | --- | --- | --- |
| Apple Speech | 已支持 | 是 | Apple Speech / `SFSpeechRecognizer` | 不下载模型，快速开始 |
| Qwen3-ASR 0.6B | 已支持 | partial + final | speech-swift `Qwen3ASR` / MLX 4bit | 日常本地听写，体积和速度均衡 |
| Qwen3-ASR 1.7B | 已支持 | partial + final | speech-swift `Qwen3ASR` / MLX 8bit | 更高准确率，需要更多内存 |
| Whisper Turbo / Large V3 | 已支持 | 否 | WhisperKit `.mlmodelc` | 录音结束后的高质量完整转写 |
| FunASR | 已支持 | 片段确认 | Sherpa-ONNX | 中文本地备选，不依赖 CoreML |
| SenseVoice | 已支持 | 短句/非流式路径 | FluidAudio / CoreML | 本地多语种短句转写 |
| Paraformer Large zh | 已支持 | 片段确认 | FluidAudio / CoreML int8 | 中文本地转写 |
| NVIDIA Nemotron 0.6B | 已支持 | 是 | speech-swift `NemotronStreamingASR` / CoreML | 本地多语言流式候选 |
| Parakeet Streaming | 已支持 | 是 | speech-swift `ParakeetStreamingASR` / CoreML | 英文和欧洲语种低延迟听写 |
| Omnilingual ASR | 已支持 | 否 | speech-swift `OmnilingualASR` / CoreML | 广语言离线转写和实验场景 |

## 云端 Provider

云端 Provider 会把录音发送给所选服务商。凭据默认保存在本地凭据文件中。

| 云端 Provider | 状态 | 流式能力 | 默认模型 / 接口 | 配置项 |
| --- | --- | --- | --- | --- |
| Groq | 已支持 | 否 | `whisper-large-v3-turbo` audio transcription | API Key、模型 |
| 腾讯云 | 已支持 | 是 | 实时语音识别 WebSocket，`16k_zh` | AppID、SecretId、SecretKey |
| 阿里云 | 已支持 | 是 | DashScope WebSocket，`fun-asr-realtime` | 百炼 API Key |
| 火山云 | 计划 | 计划 | 豆包流式 ASR | 待定 |
| Mistral Voxtral | 尚未支持 | 待定 | Voxtral 语音能力 | 无 |
| AssemblyAI | 尚未支持 | 待定 | AssemblyAI Transcription | 无 |
| ElevenLabs Scribe | 尚未支持 | 待定 | ElevenLabs Scribe | 无 |

## 选择语义

码上写只会在 Provider 可选时持久化 selected provider。本地模型缺失或云端凭据未配置时，选择会被拒绝，而不是把一个不可用 Provider 写进设置后再运行时静默 fallback。

如果旧设置里已经保存了某个 Provider，但后来模型目录被删除或状态不可用，运行时仍可 fallback 到 Apple Speech。

## 怎么选

- 想最快开始：Apple Speech。
- 日常本地听写：Qwen3-ASR 0.6B。
- 更重视准确率：Qwen3-ASR 1.7B。
- 文件或录音高质量转写：Whisper。
- 云端实时中文：腾讯云或阿里云。
- 不想下载本地模型但能接受云端最终转写：Groq。
