# VoxFlow 资源归属

本文记录 SwiftPM target 迁移期间的运行时与打包资源归属。“当前归属”指当下实际打包该文件的 target 或构建步骤；“目标归属”指后续把资源从 app 壳层迁出时的预期归属。

## 打包资源

| 路径 | 当前归属 | 目标归属 | 备注 |
| --- | --- | --- | --- |
| `Resources/AppIcon.icns` | `Makefile` app bundle 打包 | `VoxFlowApp` | 复制到 `VoxFlow.app/Contents/Resources`，并被 `Info.plist` 引用。 |
| `Resources/AppIcon.iconset/icon_16x16.png` | App 图标源资产 | `VoxFlowApp` | 重新生成 `AppIcon.icns` 用的源图。 |
| `Resources/AppIcon.iconset/icon_16x16@2x.png` | App 图标源资产 | `VoxFlowApp` | 重新生成 `AppIcon.icns` 用的源图。 |
| `Resources/AppIcon.iconset/icon_32x32.png` | App 图标源资产 | `VoxFlowApp` | 重新生成 `AppIcon.icns` 用的源图。 |
| `Resources/AppIcon.iconset/icon_32x32@2x.png` | App 图标源资产 | `VoxFlowApp` | 重新生成 `AppIcon.icns` 用的源图。 |
| `Resources/AppIcon.iconset/icon_128x128.png` | App 图标源资产 | `VoxFlowApp` | 重新生成 `AppIcon.icns` 用的源图。 |
| `Resources/AppIcon.iconset/icon_128x128@2x.png` | App 图标源资产 | `VoxFlowApp` | 重新生成 `AppIcon.icns` 用的源图。 |
| `Resources/AppIcon.iconset/icon_256x256.png` | App 图标源资产 | `VoxFlowApp` | 重新生成 `AppIcon.icns` 用的源图。 |
| `Resources/AppIcon.iconset/icon_256x256@2x.png` | App 图标源资产 | `VoxFlowApp` | 重新生成 `AppIcon.icns` 用的源图。 |
| `Resources/AppIcon.iconset/icon_512x512.png` | App 图标源资产 | `VoxFlowApp` | 重新生成 `AppIcon.icns` 用的源图。 |
| `Resources/AppIcon.iconset/icon_512x512@2x.png` | App 图标源资产 | `VoxFlowApp` | 重新生成 `AppIcon.icns` 用的源图。 |
| `Sources/VoxFlowApp/Resources/Info.plist` | `Makefile` app bundle 打包 | `VoxFlowApp` | 不进入 SwiftPM resources，作为 bundle `Info.plist` 单独复制。 |
| `Packages/VoxFlowR2T2Core/LICENSE`、`Packages/VoxFlowR2T2Core/NOTICE` | `Makefile` app bundle 打包（`COPY_THIRD_PARTY_NOTICES`） | 同左 | 复制到 `VoxFlow.app/Contents/Resources/ThirdPartyNotices/VoxFlowR2T2Core-{LICENSE,NOTICE}.txt`；源文件只在 package 内保留一份，`make build` / `build-native` / `build-dev` 都会复制并断言存在。完整第三方归属见 `docs/third-party-licenses.md`。 |
| `Sources/VoxFlowProviders/VoxFlowProviderXASR/Resources/xasr-canary.f32` | `VoxFlowProviderXASR` SwiftPM resource bundle，Makefile 复制到 App Resources | 同左 | 系统现有 TTS 合成的「你好，这是语音识别测试。」诊断音频，16kHz mono Float32，约158KiB；不含用户录音或模型权重。通过实际打包资源 bundle 查找，不依赖构建目录绝对路径。 |

## 运行时 UI 资源

| 路径 | 当前归属 | 目标归属 | 备注 |
| --- | --- | --- | --- |
| `Sources/VoxFlowApp/Resources/AuthorWeChatQRCode.jpg` | `VoxFlowApp` SwiftPM resource bundle | `VoxFlowFeatures` | 帮助 / 关于界面渲染。 |
| `Sources/VoxFlowApp/Resources/UserGroupQRCode.jpg` | `VoxFlowApp` SwiftPM resource bundle | `VoxFlowFeatures` | 帮助页社区用户群二维码。 |
| `Sources/VoxFlowApp/Resources/GitHubMark.png` | `VoxFlowApp` SwiftPM resource bundle | `VoxFlowDesignSystem` | 作为模板图加载，用于主题着色。 |
| `Sources/VoxFlowApp/Resources/ASRAppleSpeech.png` | `VoxFlowApp` SwiftPM resource bundle | `VoxFlowProviderApple` | Apple Speech Provider 卡片图标。 |
| `Sources/VoxFlowApp/Resources/ASRAssemblyAI.png` | `VoxFlowApp` SwiftPM resource bundle | 在线 ASR 目录 | AssemblyAI Provider 卡片图标。 |
| `Sources/VoxFlowApp/Resources/ASRConfucius.png` | `VoxFlowApp` SwiftPM resource bundle | `VoxFlowProviderR2T2` | Confucius4-R2T2 Provider 卡片图标；参考上游 R2T2 官方标识后生成的 128×128 单色透明图标。 |
| `Sources/VoxFlowApp/Resources/ASRDoubao.png` | `VoxFlowApp` SwiftPM resource bundle | 在线 ASR 目录 | 火山引擎 Doubao ASR Provider 卡片图标。 |
| `Sources/VoxFlowApp/Resources/ASRElevenLabs.png` | `VoxFlowApp` SwiftPM resource bundle | 在线 ASR 目录 | ElevenLabs Scribe Provider 卡片图标。 |
| `Sources/VoxFlowApp/Resources/ASRFireRedASR.png` | `VoxFlowApp` SwiftPM resource bundle | `VoxFlowProviderFireRedASR` | FireRedASR2-AED Provider 卡片图标；参考上游 FireRedTeam 官方标识后生成的 128×128 单色透明图标。 |
| `Sources/VoxFlowApp/Resources/ASRFunASR.png` | `VoxFlowApp` SwiftPM resource bundle | `VoxFlowProviderFunASR` | FunASR Provider 卡片图标。 |
| `Sources/VoxFlowApp/Resources/ASRGroqWhisper.png` | `VoxFlowApp` SwiftPM resource bundle | 在线 ASR 目录 | Groq Whisper Provider 卡片图标。 |
| `Sources/VoxFlowApp/Resources/ASRMistralVoxtral.png` | `VoxFlowApp` SwiftPM resource bundle | 在线 ASR 目录 | Mistral Voxtral Provider 卡片图标。 |
| `Sources/VoxFlowApp/Resources/ASRNVIDIANemotron.png` | `VoxFlowApp` SwiftPM resource bundle | `VoxFlowProviderNVIDIA` | NVIDIA Nemotron ASR Provider 卡片图标。 |
| `Sources/VoxFlowApp/Resources/ASROmnilingual.png` | `VoxFlowApp` SwiftPM resource bundle | `VoxFlowProviderOmnilingual` | Omnilingual ASR Provider 卡片图标。 |
| `Sources/VoxFlowApp/Resources/ASRParakeetStreaming.png` | `VoxFlowApp` SwiftPM resource bundle | `VoxFlowProviderParakeet` | Parakeet Streaming Provider 卡片图标。 |
| `Sources/VoxFlowApp/Resources/ASRProviderParaformer.png` | `VoxFlowApp` SwiftPM resource bundle | `VoxFlowProviderParaformer` | Paraformer Provider 卡片图标。 |
| `Sources/VoxFlowApp/Resources/ASRProviderIconAtlas.json` | `VoxFlowApp` SwiftPM resource bundle | `VoxFlowDesignSystem` | Provider ID 到 bundle 内图标资产的图集映射。 |
| `Sources/VoxFlowApp/Resources/ASRQwen.png` | `VoxFlowApp` SwiftPM resource bundle | `VoxFlowProviderQwen3` | Qwen3-ASR Provider 卡片图标。 |
| `Sources/VoxFlowApp/Resources/ASRQwenCloud.png` | `VoxFlowApp` SwiftPM resource bundle | 在线 ASR 目录 | Qwen Cloud ASR Provider 卡片图标。 |
| `Sources/VoxFlowApp/Resources/ASRSenseVoice.png` | `VoxFlowApp` SwiftPM resource bundle | `VoxFlowProviderSenseVoice` | SenseVoice Provider 卡片图标。 |
| `Sources/VoxFlowApp/Resources/ASRTencentCloud.png` | `VoxFlowApp` SwiftPM resource bundle | 在线 ASR 目录 | 腾讯云 ASR Provider 卡片图标。 |
| `Sources/VoxFlowApp/Resources/ASRWhisper.png` | `VoxFlowApp` SwiftPM resource bundle | `VoxFlowProviderWhisper` | Whisper Provider 卡片图标。 |

## 下载的模型权重（不打包）

以下权重由用户在设置页显式发起后经 `VoxFlowModelStore` 下载到 `~/Library/Application Support/VoxFlow/models/`，**不进入 App bundle、仓库或测试 fixture**。删除 App 或清理模型时按各自许可与 ModelStore 的删除流程处理。

| 模型 | 来源（固定 revision） | 磁盘占用 | 许可 | 备注 |
| --- | --- | --- | --- | --- |
| FireRedASR2-AED int8 | `sherpa-onnx` release 资产 `sherpa-onnx-fire-red-asr2-zh_en-int8-2026-02-26.tar.bz2`（固定 tag 资产，转换自 ModelScope `FireRedTeam/FireRedASR2-AED`） | 1,234,657,933 B（≈1.15 GiB），3 个必需文件（`encoder.int8.onnx` / `decoder.int8.onnx` / `tokens.txt`） | 上游代码仓库为 Apache-2.0；**权重资产本身不含 LICENSE，条款待发布前确认** | 语音仅在本机推理，不联网；内存门槛 16 GB。离线 AED 支持滚动重解预览，final 由权威整段重解产出。安装位置 `~/Library/Application Support/VoxFlow/models/fireredasr-aed-int8/<版本目录>/`，经 ModelStore 清单校验（归档 sha256 + 逐组件 sha256）与原子换入。URL、大小与 hash 见 `Sources/VoxFlowProviders/VoxFlowProviderFireRedASR/Runtime/FireRedASRModel.swift` 与同目录 `Manifest/FireRedASRManifestCatalog.swift`，接入说明见 `docs/third-party-licenses.md`。 |
| Confucius4-R2T2-8bit | `mlx-community/Confucius4-R2T2-8bit` @ `2d6d997c3e09c65a65b1b2576b6b9b7728df8eab` | 2,479,303,980 B（≈2.31 GiB），10 个文件（含 `LICENSE` / `MODEL_LICENSE_zh` / `NOTICE`） | NetEase Youdao Model Use License Agreement | 只支持 arm64 + macOS 15+，至少 16 GB 内存、推荐 24 GB；稳定前缀解码，未确认尾部可修订。清单与 hash 见 `Sources/VoxFlowProviders/VoxFlowProviderR2T2/Manifest/R2T2ManifestCatalog.swift`，上游与衍化说明见 `Packages/VoxFlowR2T2Core/PROVENANCE.md`。权重许可与归属文件随权重一起安装到模型目录，缺失会被 readiness 判定为需要修复。 |
| X-ASR-zh-en 480ms | `GilgameshWind/X-ASR-zh-en` @ `689ff18c584d29910da37b6fe904db0c1489c9d1`，`deployment/models/chunk-480ms-model/` | 614,596,718 B（≈586MiB），encoder/decoder/joiner/tokens 四文件 | 固定版本官方模型卡声明 Apache-2.0 | 原生 arm64、macOS15+、8GiB门槛（低配性能未验证）；安装至 `Models/xasr-zh-en-480ms/<revision>/`，逐文件校验、原子安装、真实canary；默认C runtime创建前复验size/hash。清单见 `Sources/VoxFlowProviders/VoxFlowProviderXASR/Manifest/XASRManifestCatalog.swift`。 |

注意：R2T2 的**推理代码**（`Packages/VoxFlowR2T2Core`）是 MIT，与上述**权重许可互相独立**。发布前需单独确认权重许可的规模门槛与使用限制。

## X-ASR 验证资产与交付边界

X-ASR 的 Provider 和固定 ModelStore 清单已实现，继续复用 sherpa-onnx1.13.3，不新增 Python 运行时。160ms候选、官方录音转换和性能探针的临时资产仅用于开发验证，不打包或列为用户可选档位。模型已通过真权重M0和正式runtime/安装canary测试；完整App入口和低配机器验收尚未完成，不从下载大小推导性能。

## 迁移规则

新增运行时资源必须放到归属 target 的 resource 目录，或在同一改动里补充本文记录。打包资源必须写明把它装进 `VoxFlow.app` 的构建步骤。
