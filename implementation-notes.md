## LLM 流式解码、本地模型下载与设置反馈修复 - 2026-06-16

**目标**：修复 OpenAI 兼容流式响应中文乱码、本地 Qwen3-ASR 1.7B 下载后仍显示未安装，以及模型设置页无法明确识别当前全局模型的问题。

**设计决策**：流式响应按 SSE 事件积累原始字节后统一用 UTF-8 解码，而不是逐字节转成 UnicodeScalar；Qwen3-ASR 1.7B 下载清单补充共享 `vocab.json`，下载完成后再校验必要文件；设置页在根视图统一承载嵌入页面的反馈 toast。

**偏差说明**：原问题集中在流式识别和下载状态，实际排查发现设置页的默认模型选择与反馈位置也会放大误解，因此一并收敛 UI 状态表达。

**权衡分析**：
- 方案一：只修当前触发点。优点是改动更少；缺点是用户仍可能看不出默认模型和下载失败原因。

---

## 多本地 ASR 模型支持与菜单栏平铺 - 2026-06-16

**目标**：在设置页增加 FunASR、Whisper、Paraformer、SenseVoice Small 四个本地 ASR 模型的占位支持；在菜单栏"语音识别引擎"子菜单中，将 Qwen3-ASR 的两个尺寸（0.6B、1.7B）平铺为独立菜单项，新模型也一并平铺显示。

**设计决策**：
- ASREngineType 枚举新增 `.funASR`、`.whisper`、`.paraformer`、`.senseVoice` 四例，MockASREngine 在缺乏原生库环境下返回逼真的模拟结果。
- AppDelegate 的 ASR 引擎菜单改为使用 `ASRMenuModel` 扁平结构，每个 Qwen 尺寸独立成项，选中时同时设置引擎类型和模型尺寸。
- `ASRManager` 增加每个模型的独立路径属性，并为 Qwen 提供 `qwen3ModelPath(for:)`（按特定尺寸搜索磁盘）+ `isQwen3ModelAvailableOnDisk(for:)`（菜单启用检查），同时保留原 `isQwen3ModelAvailable`（仅 UserDefaults 路径）确保现有测试兼容。
- `ASRProviderRegistry` 为每个本地模型定义高还原度描述符，包含图片展示的参数特征标签（模型精度、语言支持、文件大小等）。
- `ASRProviderViewModel` 提供通用 `downloadModel(id:)` / `deleteLocalModel(id:)`，通过 `asrManager` 属性读写确保测试 UserDefaults 隔离；新模型下载表现为带进度条的 10 步模拟，并在 `~/Library/Application Support/VoiceInput/Models/<dir>/` 下生成 `metadata.json` 伪文件标记存在。

**偏差说明**：新模型无原生 CoreML 库依赖，当前以 `MockASREngine` 返回模拟转录结果，后续接入真实推理引擎时替换 `makeEngine` 实现即可。

**权衡分析**：
- 方案一（当前实现）：菜单栏平铺全部 7 个选项（系统自带 + 6 个本地模型）。优点：用户一眼可见全部选择；缺点：选项较多可能拥挤。选择此方案因为用户明确要求"平铺开"。
- 方案二：将 Qwen 尺寸折叠到二级子菜单。优点：节省一级菜单空间；缺点：与用户需求相悖。

**待确认**：
- [ ] FunASR/Whisper/Paraformer/SenseVoice Small 的模拟下载是否满足预期行为？
- [ ] 菜单栏平铺后的视觉效果是否需要调整？
- 方案二：修根因并补齐状态表达。优点是乱码、假成功、默认模型不清晰三个链路同时闭环；缺点是涉及更多视图与测试。
- 选择方案二，因为这些问题在同一配置链路中相互影响，单点修复不足以恢复可理解性。

**待确认**：
- [ ] 实机设置页视觉是否符合预期？
- [ ] 是否需要对已存在但缺少 `vocab.json` 的 1.7B 本地目录提供一键修复？

## LLM 选模型交互与排序对齐 - 2026-06-16

**目标**：让 LLM 模型的点击交互和语音/听写模型完全对齐（点击卡片即可选中，无需单独的勾选按钮），修复手势冲突导致测试连接不响应，并解决点击选中后卡片顺序发生置顶跳变的问题。

**设计决策**：
- 移除原本 LLM 卡片中独立的勾选设为默认按钮（`checkmark.circle`）以及顶部的 `defaultProviderSummary` 区域。
- 采用与语音模型相同的卡片高亮和 "当前使用" 标记，将左侧点击内容区域封装为 Button 实现直接选中。
- 修复点击手势吞没子 Button 事件的 macOS 系统交互特性（解决点击测试连接无响应）。
- 调整 LLM 数据库列表查询的排序规则，从 `is_default DESC, display_name ASC` 改为 `created_at ASC, display_name ASC`，使卡片保持固定的创建顺序，不会在选中或刷新时发生置顶重排。

**偏差说明**：原需求主要是希望选哪个就高亮哪个并且去掉勾选 icon，但在重构和测试过程中发现手势冲突吞按钮和数据库默认排序跳变也会极大影响用户体验，因此对这些深层交互行为进行了一并对齐与修复。

**权衡分析**：
- 方案一：使用 `.onTapGesture` 并保留卡片原样。优点是视图结构简单，缺点是会吞掉卡片内部按钮（编辑、测试、删除）的点击事件，且选中后由于默认数据库排序是 `is_default DESC`，选中的卡片会自动移到首位发生闪烁跳变。
- 方案二：采用兄弟节点 Button 分离手势，并修改 Repository 查询排序为 `created_at ASC`。优点是测试连接响应完美、卡片顺序保持固定，与 ASR 语音模型视图交互及稳定性完美对齐。
- 选择方案二，因为这是保证 macOS 桌面设置页交互跟手、稳健及一致性的最佳实践。

**待确认**：
- [ ] 交互体验是否比之前更流畅、卡片在点击后依然保持顺序是否满意？
- [ ] 是否需要将 ASR 与 LLM 的数据加载方式全部做成统一的 Repository 管理？

## LLM 连接测试按钮与 Toast 显示修复 - 2026-06-16

**目标**：修复模型服务卡片和编辑弹窗中的连接测试缺少点击反馈，以及测试完成后 toast 不显示的问题。

**设计决策**：将卡片选择区域改为独立 Button，与编辑、测试、删除按钮并列，避免父级手势竞争；连接测试状态统一由 LLMProviderViewModel 暴露；toast 收到 message/error 后立即渲染，异步任务只负责自动清除。

**偏差说明**：最初判断只有卡片父级手势吞事件；用户实测后确认 toast 仍不显示，进一步定位到 ActionFeedbackView 依赖空视图上的 task 将 isVisible 从 false 切为 true，该任务可能没有启动。

**权衡分析**：
- 保留 isVisible 自举：改动更少，但首次渲染依赖空视图生命周期，不可靠。
- 直接按反馈内容渲染：状态更少，message/error 是唯一显示来源，选择此方案。

**待确认**：
- [ ] 实机点击外部测试和编辑弹窗测试时，spinner 与成功/失败 toast 是否均正常显示？

## LLM 当前模型卡片选中态颜色修复 - 2026-06-16

**目标**：修复 LLM 当前使用卡片内容被系统自动降透明度、视觉上与 ASR 当前模型卡片不一致的问题。

**设计决策**：默认服务不再禁用卡片选择 Button，仅在服务本身停用时禁用；重复选择仍由 Button action 内的 guard 阻止。

**偏差说明**：颜色 token 本身没有变化，实际根因是 SwiftUI 对 disabled Button label 自动应用了弱化样式。

**权衡分析**：
- 保留默认态 disabled 并手动覆盖透明度：会与系统 disabled 语义冲突。
- 仅禁用已停用服务：保持默认卡片正常配色，同时不改变选择行为，选择此方案。

**待确认**：
- [ ] 实机选中态是否与 ASR 卡片视觉一致？

## ASR 真实后端、模型配置与发布构建修复 - 2026-06-16

**目标**：移除会损坏 Qwen embedding 的原地修补逻辑，撤掉不被当前推理栈支持的 Qwen3-ASR 1.7B，将新增 ASR provider 从 mock/metadata 占位改为真实本地识别后端，并修复 LLM 测试按钮 toast 与 release 构建产物不刷新的问题。

**设计决策**：
- Qwen3-ASR 只保留 0.6B；manifest 校验 embedding 头和精确文件大小，不再尝试在设置页或下载后原地插入 header。
- FunASR 与 Paraformer 使用 sherpa-onnx 静态库；FunASR 支持 INT8/FP32，Paraformer 支持中文/English，下载后必须存在非空模型文件才算可用。
- SenseVoice 使用 FluidAudio 真实模型，但绕开会在当前 macOS/XCTest 环境卡住的 ANE int8 编译路径，改为 `fp32` fallback，并在 VoxFlow 侧补齐固定 1800 帧输入 padding；Whisper 改用 Argmax WhisperKit Core ML 压缩模型，避免 sherpa Whisper 展开后数 GB 到 8GB 的模型体积。
- ASR 设置页、菜单栏和 UserDefaults 都使用同一组选项：FunASR INT8/FP32、Whisper Turbo/Large V3、Paraformer 中文/English、Qwen3 0.6B、SenseVoice、Apple。
- ASR icon 使用官方项目/组织来源生成的资源图片，并在 App 内按模板图渲染为项目绿色。
- LLM provider 卡片把选择区域和编辑/测试/删除按钮拆成兄弟 Button，toast 按 message/error 立即渲染；编辑弹窗也挂载独立反馈层。
- HUD 临时消息的 dismiss 不再完全依赖 AppKit animation completion，增加同 generation 的 async fallback，避免测试/运行时 completion 不回调导致提示不消失。
- `make build` 改为 arm64 与 x86_64 分开 release 构建再用 `lipo` 合成 Universal Binary，绕开 WhisperKit 依赖中 CLI product 导致的 SwiftPM 多架构重复 key 问题；资源 bundle 校验改为 SwiftPM 当前扁平目录结构。

**偏差说明**：原计划可以暂时隐藏新增 provider，但最终实现选择接入真实后端而不是继续保留空壳。Whisper 没有继续使用 sherpa-onnx，是因为官方 sherpa Whisper Large/Turbo 包展开体积过大，不适合设置页内的“下载模型即可使用”体验。

**权衡分析**：
- 方案一：仅隐藏 mock provider。优点是改动小；缺点是用户仍无法使用 FunASR、Whisper、Paraformer、SenseVoice。
- 方案二：接入 sherpa-onnx、FluidAudio、WhisperKit 三条真实本地路径。优点是所有展示的 provider 都有真实识别引擎；缺点是构建链和模型下载逻辑更复杂。
- 选择方案二，因为用户明确要求“所有模型都是能够成功进行语音识别的”，继续保留 mock 或空壳会再次误导。

**待确认**：
- [ ] 是否需要在 UI 中显示各模型真实下载大小和预计磁盘占用？
- [ ] 是否需要提供已损坏 Qwen embedding 文件的一键删除/重新下载入口？
- [ ] 是否接受 Whisper 使用 WhisperKit 官方 Core ML 模型，而不是 sherpa-onnx Whisper 包？

**验证记录**：
- `swift test`：510 tests, 7 skipped, 0 failures。
- `make debug`：通过，warnings-as-errors 无告警。
- `make build`：通过，生成并签名 Universal Binary（arm64 + x86_64）。
- `make run` + Computer Use：新产物启动后，LLM 卡片外层测试和编辑弹窗测试均显示“连接测试成功” toast。
- `VOICEINPUT_TEST_QWEN3_LIVE=1 swift test --filter Qwen3LiveSmokeTests`：Qwen3-ASR 0.6B 真实模型加载和音频路径通过。
- `VOICEINPUT_TEST_SHERPA_LIVE=1 VOICEINPUT_TEST_SHERPA_VARIANT=funASRInt8 ... swift test --filter SherpaLiveSmokeTests`：FunASR Nano INT8 官方模型真实转写通过。
- `VOICEINPUT_TEST_SHERPA_LIVE=1 VOICEINPUT_TEST_SHERPA_VARIANT=funASRFP32 ... swift test --filter SherpaLiveSmokeTests`：FunASR Nano FP32 官方模型真实转写通过。
- `VOICEINPUT_TEST_SHERPA_LIVE=1 VOICEINPUT_TEST_SHERPA_VARIANT=paraformerChinese ... swift test --filter SherpaLiveSmokeTests`：Paraformer 中文官方模型真实转写通过。
- `VOICEINPUT_TEST_SHERPA_LIVE=1 VOICEINPUT_TEST_SHERPA_VARIANT=paraformerEnglish ... swift test --filter SherpaLiveSmokeTests`：Paraformer English 官方模型真实转写通过。
- `VOICEINPUT_TEST_WHISPERKIT_LIVE=1 VOICEINPUT_TEST_WHISPERKIT_VARIANT=turbo ... swift test --filter WhisperKitLiveSmokeTests`：Whisper Turbo 官方 Core ML 模型真实转写通过，首次 Core ML 编译耗时约 136 秒。
- `VOICEINPUT_TEST_WHISPERKIT_LIVE=1 VOICEINPUT_TEST_WHISPERKIT_VARIANT=largeV3 ... swift test --filter WhisperKitLiveSmokeTests`：Whisper Large V3 官方 Core ML 模型真实转写通过。
- `VOICEINPUT_TEST_FLUIDAUDIO_LIVE=1 VOICEINPUT_TEST_FLUIDAUDIO_MODEL=senseVoice ... swift test --filter FluidAudioLiveSmokeTests`：SenseVoice Small FluidAudio fp32 模型真实转写通过。

## ASR 模型回归复查与 SenseVoice 修正 - 2026-06-16

**目标**：复查 Qwen3-ASR 质量退化、SenseVoice 识别异常、ASR 卡片空白区域不可点击和系统/provider logo 不符合预期的问题。

**设计决策**：SenseVoice 撤回 VoxFlow 侧自写的 fp32 CTC fallback，改回 FluidAudio 官方 `SenseVoiceManager`，使用官方默认的 FP16 encoder 路径和 bucket padding；ASR 卡片选择交互采用透明背景 Button，避免父级 tap gesture 吞掉内部下载/删除控件；系统自带 provider 使用 SF Symbol `apple.logo`；FunASR/Qwen3/SenseVoice 在缺少可靠官方独立 logo 时使用文字徽标，避免继续展示伪官方资源；Qwen3-ASR 恢复 0.6B/1.7B 两个型号入口，但 1.7B 只作为已知型号展示，下载时给出明确“不支持当前 CoreML 运行时”的错误，避免再次制造可下载但不可运行的空壳。

**偏差说明**：本地参考应用可查看的是打包 app 和模型目录，不是源码；它的 Qwen 路线是 ONNX encoder frontend/backend + GGUF decoder worker，而当前 VoxFlow 使用 FluidAudio CoreML 0.6B beta 路线。直接把 1.7B 放进现有 CoreML engine 会继续坏，因为 FluidAudio runtime 关键配置仍按 0.6B/1024 hidden size 运行。

**权衡分析**：
- 方案一：直接恢复 1.7B 下载并沿用现有 `Qwen3ASREngine`。优点是 UI 看起来回来了；缺点是下载后大概率不可用或质量继续异常。
- 方案二：恢复 1.7B 可见性但阻止虚假下载，同时记录需要接 ONNX/GGUF worker 才能真正恢复旧质量。选择此方案，因为它不会把未接好的 provider 包装成可用能力。
- 方案三：立刻引入参考应用同款 worker 二进制。优点是最接近旧质量；缺点是本仓库没有源码/授权边界不清，且分发风险较高。

**待确认**：
- [ ] 是否要为 Qwen3-ASR 新增独立 ONNX/GGUF worker runtime，以恢复参考应用同款 0.6B/1.7B 质量路径？
- [ ] FunASR/SenseVoice 是否需要继续寻找官方品牌图；若官方没有独立 logo，是否接受文字/项目缩写图标而非伪官方 PNG？

**验证记录**：
- `swift test --filter 'ASRProviderIconTests|ASRProviderViewPresentationTests'`：5 tests, 0 failures。
- `swift test`：517 tests, 7 skipped, 0 failures。
- `make debug`：通过，warnings-as-errors 无告警。
- `VOICEINPUT_TEST_FLUIDAUDIO_LIVE=1 VOICEINPUT_TEST_FLUIDAUDIO_MODEL=senseVoice VOICEINPUT_TEST_FLUIDAUDIO_WAVE_PATH=/tmp/voxflow-sensevoice-zh.aiff swift test --filter FluidAudioLiveSmokeTests/testConfiguredFluidAudioModelLoadsAndTranscribesWave`：通过，加载 `SenseVoice (encoder: fp16, vocab: 25055)`，耗时约 86 秒。
- `make build`：通过，生成并签名 `.build/VoxFlow.app`。
