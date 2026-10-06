# 语音模型

码上写支持开箱可用的 Apple Speech、本地 ASR Provider，以及可选云端 Provider。模型页会明确标注本地/云端、流式能力、语言覆盖和可用状态。「本地离线」表示无需云端识别，不代表无法流式处理；X-ASR 就是在本机运行的原生流式模型。

## 本地和系统 Provider

本地 Provider 会把音频留在 Mac 上处理；Apple Speech 的行为由 macOS 系统服务决定。

下表描述 macOS 版，不代表相同模型已经接入 Windows 或 iOS。「已支持」指运行时已接入，实际可用性仍取决于模型安装状态和硬件预检。

| Provider / 模型 | 状态 | 流式能力 | 运行路线 | 推荐用途 |
| --- | --- | --- | --- | --- |
| Apple Speech | 已支持 | 是 | Apple Speech / `SFSpeechRecognizer` | 不下载模型，快速开始 |
| Qwen3-ASR 0.6B | 已支持 | partial + final | speech-swift `Qwen3ASR` / MLX 4bit | 日常本地听写，体积和速度均衡 |
| Qwen3-ASR 1.7B | 已支持 | partial + final | speech-swift `Qwen3ASR` / MLX 8bit | 更高准确率，需要更多内存 |
| Confucius4-R2T2 | 已支持 | 稳定前缀 + 可修订尾部预览 | `VoxFlowR2T2Core` / MLX 8bit | Apple Silicon 上的中英本地听写与实时反馈 |
| FireRedASR2-AED | 已支持 | 滚动重解预览；整段重解得到 final | vendored sherpa-onnx / AED int8 | 侧重中文与方言覆盖，需等待最终解码 |
| Whisper Turbo / Large V3 | 已支持 | 否 | WhisperKit `.mlmodelc` | 录音结束后的高质量完整转写 |
| FunASR | 已支持 | 片段确认 | Sherpa-ONNX | 中文本地备选，不依赖 CoreML |
| SenseVoice | 已支持 | 短句/非流式路径 | FluidAudio / CoreML | 本地多语种短句转写 |
| Paraformer Large zh | 已支持 | 片段确认 | FluidAudio / CoreML int8 | 中文本地转写 |
| NVIDIA Nemotron 0.6B | 已支持 | 是 | speech-swift `NemotronStreamingASR` / CoreML | 本地多语言流式候选 |
| Parakeet Streaming | 已支持 | 是 | speech-swift `ParakeetStreamingASR` / CoreML | 英文和欧洲语种低延迟听写 |
| Omnilingual ASR | 已支持 | 否 | speech-swift `OmnilingualASR` / CoreML | 广语言离线转写和实验场景 |
| X-ASR-zh-en | 开发源码已接入，完整验收中 | 原生增量解码 | 现有 sherpa-onnx 1.13.3 Online C API | Apple Silicon 中英流式听写，8 GiB 内存门槛 |

### 最近新增的本地模型

- **Confucius4-R2T2**：仅支持 Apple Silicon、macOS 15+，至少 16 GB 内存，推荐 24 GB。固定版本 8bit 模型约占 2.31 GiB。已确认前缀只增长，未确认尾部可以在后续步骤修订；它与既有 Qwen3-ASR 是两个独立 Provider。
- **FireRedASR2-AED**：要求 macOS 15+ 和至少 16 GB 内存。安装后的 AED int8 文件约占 1.15 GiB（1.24 GB），下载归档及解包暂存还需要额外空间。实时预览在至少新增 1 秒音频且没有预览解码在运行时重解已累积音频；最终文本仍来自单独的整段重解，超过 50 秒的录音采用静音优先切片。因此它是带实时预览的离线模型，不是原生增量解码模型。
- 上述两个已接入 Provider 都沿用「本地模型实时预览」开关，由用户主动下载权重，不改变默认 Provider。R2T2 支持通过提示上下文传递词汇，FireRedASR 当前没有热词下发接口；提示上下文与解码器原生热词加权是不同能力。「代码已接入」不等于所有机型和麦克风入口已完成真机验收。
- **X-ASR-zh-en**：开发源码已接入，要求 Apple Silicon、macOS 15+，设 8 GiB 内存门槛，低配机型尚未实测。固定 480ms 档位四文件共 614,596,718 bytes（约 586 MiB），复用 sherpa-onnx 1.13.3，缓存 recognizer，收尾补零 1 秒保留末字。真模型短样本通常收到约 1.5–1.6 秒音频后首次出字；480ms 是模型档位，不是出字延迟承诺。已验证正式 App 音频链路的 5 分钟回放，物理麦克风和 UI 验收仍待完成。首版不开放文件工作台转写、热词或自动分句提交，不算入此前准备的 v1.17.0 发布说明。

在「设置 → 模型」展开对应卡片下载；文件校验、原子安装和真实推理 canary 完成后才能选择。三者均沿用本地实时预览设置，但 FireRedASR 当前关闭的是显示而非预览计算，该限制是已记录的现状，不代表优化已交付。

模型归属与许可见[资源归属](../resource-ownership.md)。

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
- Apple Silicon 上需要中英本地听写和实时反馈，且内存满足门槛：Confucius4-R2T2。
- 侧重中文或方言，能够接受较重模型及最终解码等待：可尝试 FireRedASR2-AED。
- 文件或录音高质量转写：Whisper。
- 云端实时中文：腾讯云或阿里云。
- 不想下载本地模型但能接受云端最终转写：Groq。
