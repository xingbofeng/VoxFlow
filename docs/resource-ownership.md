# VoxFlow Resource Ownership

This document records runtime and packaging resource ownership during the
SwiftPM target migration. "Current owner" is the target or build step that
ships the file today. "Target owner" is the intended owner if the resource is
moved out of the app shell later.

## Packaging Resources

| Path | Current owner | Target owner | Notes |
| --- | --- | --- | --- |
| `Resources/AppIcon.icns` | `Makefile` app bundle packaging | `VoxFlowApp` | Copied into `VoxFlow.app/Contents/Resources`; also referenced by `Info.plist`. |
| `Resources/AppIcon.iconset/icon_16x16.png` | App icon source asset | `VoxFlowApp` | Source image used to regenerate `AppIcon.icns`. |
| `Resources/AppIcon.iconset/icon_16x16@2x.png` | App icon source asset | `VoxFlowApp` | Source image used to regenerate `AppIcon.icns`. |
| `Resources/AppIcon.iconset/icon_32x32.png` | App icon source asset | `VoxFlowApp` | Source image used to regenerate `AppIcon.icns`. |
| `Resources/AppIcon.iconset/icon_32x32@2x.png` | App icon source asset | `VoxFlowApp` | Source image used to regenerate `AppIcon.icns`. |
| `Resources/AppIcon.iconset/icon_128x128.png` | App icon source asset | `VoxFlowApp` | Source image used to regenerate `AppIcon.icns`. |
| `Resources/AppIcon.iconset/icon_128x128@2x.png` | App icon source asset | `VoxFlowApp` | Source image used to regenerate `AppIcon.icns`. |
| `Resources/AppIcon.iconset/icon_256x256.png` | App icon source asset | `VoxFlowApp` | Source image used to regenerate `AppIcon.icns`. |
| `Resources/AppIcon.iconset/icon_256x256@2x.png` | App icon source asset | `VoxFlowApp` | Source image used to regenerate `AppIcon.icns`. |
| `Resources/AppIcon.iconset/icon_512x512.png` | App icon source asset | `VoxFlowApp` | Source image used to regenerate `AppIcon.icns`. |
| `Resources/AppIcon.iconset/icon_512x512@2x.png` | App icon source asset | `VoxFlowApp` | Source image used to regenerate `AppIcon.icns`. |
| `Sources/VoxFlowApp/Resources/Info.plist` | `Makefile` app bundle packaging | `VoxFlowApp` | Excluded from SwiftPM resources and copied as the bundle `Info.plist`. |

## Runtime UI Resources

| Path | Current owner | Target owner | Notes |
| --- | --- | --- | --- |
| `Sources/VoxFlowApp/Resources/AuthorWeChatQRCode.jpg` | `VoxFlowApp` SwiftPM resource bundle | `VoxFlowFeatures` | Rendered by the help/about UI. |
| `Sources/VoxFlowApp/Resources/GitHubMark.png` | `VoxFlowApp` SwiftPM resource bundle | `VoxFlowDesignSystem` | Loaded as a template image for theme tinting. |
| `Sources/VoxFlowApp/Resources/ASRAppleSpeech.png` | `VoxFlowApp` SwiftPM resource bundle | `VoxFlowProviderApple` | Provider card icon for Apple Speech. |
| `Sources/VoxFlowApp/Resources/ASRAssemblyAI.png` | `VoxFlowApp` SwiftPM resource bundle | Online ASR catalog | Provider card icon for AssemblyAI. |
| `Sources/VoxFlowApp/Resources/ASRDoubao.png` | `VoxFlowApp` SwiftPM resource bundle | Online ASR catalog | Provider card icon for Volcengine Doubao ASR. |
| `Sources/VoxFlowApp/Resources/ASRElevenLabs.png` | `VoxFlowApp` SwiftPM resource bundle | Online ASR catalog | Provider card icon for ElevenLabs Scribe. |
| `Sources/VoxFlowApp/Resources/ASRFunASR.png` | `VoxFlowApp` SwiftPM resource bundle | `VoxFlowProviderFunASR` | Provider card icon for FunASR. |
| `Sources/VoxFlowApp/Resources/ASRGroqWhisper.png` | `VoxFlowApp` SwiftPM resource bundle | Online ASR catalog | Provider card icon for Groq Whisper. |
| `Sources/VoxFlowApp/Resources/ASRMistralVoxtral.png` | `VoxFlowApp` SwiftPM resource bundle | Online ASR catalog | Provider card icon for Mistral Voxtral. |
| `Sources/VoxFlowApp/Resources/ASRNVIDIANemotron.png` | `VoxFlowApp` SwiftPM resource bundle | `VoxFlowProviderNVIDIA` | Provider card icon for NVIDIA Nemotron ASR. |
| `Sources/VoxFlowApp/Resources/ASRProviderParaformer.png` | `VoxFlowApp` SwiftPM resource bundle | `VoxFlowProviderParaformer` | Provider card icon for Paraformer. |
| `Sources/VoxFlowApp/Resources/ASRProviderIconAtlas.json` | `VoxFlowApp` SwiftPM resource bundle | `VoxFlowDesignSystem` | Atlas mapping provider IDs to bundled icon assets. |
| `Sources/VoxFlowApp/Resources/ASRQwen.png` | `VoxFlowApp` SwiftPM resource bundle | `VoxFlowProviderQwen3` | Provider card icon for Qwen3-ASR. |
| `Sources/VoxFlowApp/Resources/ASRQwenCloud.png` | `VoxFlowApp` SwiftPM resource bundle | Online ASR catalog | Provider card icon for Qwen Cloud ASR. |
| `Sources/VoxFlowApp/Resources/ASRSenseVoice.png` | `VoxFlowApp` SwiftPM resource bundle | `VoxFlowProviderSenseVoice` | Provider card icon for SenseVoice. |
| `Sources/VoxFlowApp/Resources/ASRWhisper.png` | `VoxFlowApp` SwiftPM resource bundle | `VoxFlowProviderWhisper` | Provider card icon for Whisper. |

## Migration Rule

New runtime resources must be added to the owning target's resource directory
or documented here in the same change. Packaging resources must name the build
step that installs them into `VoxFlow.app`.
