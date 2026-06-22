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

## 运行时 UI 资源

| 路径 | 当前归属 | 目标归属 | 备注 |
| --- | --- | --- | --- |
| `Sources/VoxFlowApp/Resources/AuthorWeChatQRCode.jpg` | `VoxFlowApp` SwiftPM resource bundle | `VoxFlowFeatures` | 帮助 / 关于界面渲染。 |
| `Sources/VoxFlowApp/Resources/GitHubMark.png` | `VoxFlowApp` SwiftPM resource bundle | `VoxFlowDesignSystem` | 作为模板图加载，用于主题着色。 |
| `Sources/VoxFlowApp/Resources/ASRAppleSpeech.png` | `VoxFlowApp` SwiftPM resource bundle | `VoxFlowProviderApple` | Apple Speech Provider 卡片图标。 |
| `Sources/VoxFlowApp/Resources/ASRAssemblyAI.png` | `VoxFlowApp` SwiftPM resource bundle | 在线 ASR 目录 | AssemblyAI Provider 卡片图标。 |
| `Sources/VoxFlowApp/Resources/ASRDoubao.png` | `VoxFlowApp` SwiftPM resource bundle | 在线 ASR 目录 | 火山引擎 Doubao ASR Provider 卡片图标。 |
| `Sources/VoxFlowApp/Resources/ASRElevenLabs.png` | `VoxFlowApp` SwiftPM resource bundle | 在线 ASR 目录 | ElevenLabs Scribe Provider 卡片图标。 |
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

## 迁移规则

新增运行时资源必须放到归属 target 的 resource 目录，或在同一改动里补充本文记录。打包资源必须写明把它装进 `VoxFlow.app` 的构建步骤。
