<div align="center">
  <img src="docs/assets/voiceinput-logo.png" alt="VoxFlow logo" width="128">

  <h1>碼上寫 · VoxFlow</h1>
  <p><strong>語音、截圖、錄屏、剪貼簿和 coding-agent 指令的 macOS 資產工作台。</strong></p>
  <p>按 <code>⌥Space</code> 打開啟動台，找回最近語音、截圖、錄屏和剪貼簿資產；按住說話、框選截圖、錄屏、複製內容都會沈澱為可搜尋、可複製、可復用的歷史資產。</p>

  <p>
    <img src="https://img.shields.io/badge/macOS-15%2B-111827?style=flat-square&logo=apple&logoColor=white" alt="macOS 15+">
    <a href="https://github.com/xingbofeng/VoxFlow/releases/latest"><img src="https://img.shields.io/github/v/release/xingbofeng/VoxFlow?style=flat-square&label=release" alt="Latest release"></a>
    <a href="LICENSE"><img src="https://img.shields.io/badge/license-GPL--3.0--or--later-10B981?style=flat-square" alt="License: GPL-3.0-or-later"></a>
  </p>
  <p>
    🌐 <a href="https://xingbofeng.github.io/VoxFlow/">官方網站</a>
    &nbsp;·&nbsp;
    ⬇️ <a href="https://github.com/xingbofeng/VoxFlow/releases/latest">下載最新版</a>
    &nbsp;·&nbsp;
    <a href="README.md">English</a>
    &nbsp;·&nbsp;
    <a href="README.zh-CN.md">简体中文</a>
    &nbsp;·&nbsp;
    <a href="README.zh-TW.md">繁體中文</a>
    &nbsp;·&nbsp;
    <a href="README.ja.md">日本語</a>
    &nbsp;·&nbsp;
    <a href="README.ko.md">한국어</a>
  </p>
  <p>
    <a href="docs/assets/voiceinput-demo-land.mp4"><img src="docs/assets/voiceinput-demo-land.gif" alt="介紹影片" width="100%"></a>
  </p>
</div>

## 核心能力速覽

碼上寫是一個貼在當前應用上的資產工作台和快速啟動台。它不是語音助手，不接管視窗，不自動傳送內容；它把語音、截圖、錄屏、剪貼簿和 Agent 指令沈澱為可檢索、可預覽、可復用的本地資產，再送回你正在工作的地方。

| 你想做什麼 | 怎麼觸發 | 輸出到哪裡 | 邊界 |
| --- | --- | --- | --- |
| 打開啟動台 | `⌥Space` | Raycast 風格啟動台 | 首屏預設選中“最近資產”，可鍵盤導航 |
| 找回最近資產 | 啟動台 → 最近資產 | 二級資產瀏覽器 | 語音、截圖、剪貼簿統一搜尋和篩選 |
| 語音輸入 | 按住快捷鍵說話，松開 | 當前光標位置 | 不搶焦點，不自動傳送 |
| 管理剪貼簿資產 | 複製文本、圖片、文件、鏈接或顏色 | 歷史資產 | 避免噪音規則仍會過濾不需要保存的內容 |
| 易錯詞糾錯 | ASR final 和可選 LLM 後自動運行 | 插入前文本 | 本地確定性規則，候選是否啓用由你決定 |
| 剪貼板圖片 OCR | 複製圖片後按 `⌘⇧V` | 當前光標位置 | 只處理剪貼板圖片，不啟動普通聽寫 |
| 框選截圖處理 | 按 `⌘⇧A` 框選屏幕 | OCR 結果面板 | 可繼續翻譯、總結、朗讀；識別結果可回看 |
| 划詞動作 | 選中文本後按 `⌘⇧F/J/K/L/P` | 動作 HUD 或結果面板 | F 打開動作卡；J 翻譯、K 總結、L 發給任務助手、P 發給問 AI |
| 啟動台問 AI | 啟動台輸入問題後選「問 AI」 | 問 AI 聊天 HUD | 復用已配置 LLM Provider，多輪對話，流式回復，Markdown 渲染 |
| 啟動台快速搜尋 | 啟動台輸入關鍵詞後選 Quicklink | 預設瀏覽器 | 內置 Google、Bing、Perplexity、GitHub、StackOverflow、YouTube、Bilibili、X、小紅書、淘寶、京東 |
| 啟動台打開網址 | 啟動台輸入 URL 或裸域名 | 預設瀏覽器 | 自動識別 http/https/裸域名/localhost/IP+端口，第一項即「打開網址」 |
| 截圖／錄屏記錄回看 | 工作台 → 截圖 | 本地截圖與錄屏歷史和 OCR 文本 | 本地保存，可搜尋、收藏、分頁、複製與刪除 |
| 任務助手 | 讀取當前視窗上下文 + 口述意圖 | 可複製提示詞 | 只複製，不注入，不自動提交 |
| AI Coding 助手控制台 | 說出任務助手名稱和任務 | 本地 Codex / Claude / CodeBuddy / 終端 Agent | 只投遞已註冊會話 |

## 適合誰

- 經常和 ChatGPT、Claude、Codex、Cursor 或其他 AI 工具溝通，需要快速描述需求、上下文和修改意見。
- 同時開著 Codex、Claude、CodeBuddy 或其他終端 Agent，希望用語音把指令派給對應任務助手。
- 寫代碼時常要解釋 bug、補充注釋、寫提交說明、記錄排查過程。
- 經常需要從截圖、網頁、報錯彈窗或圖片里提取文字，並進一步翻譯或總結。
- 中英文混說比較多，希望技術詞、產品名和專有名詞更穩定。

## 閱讀路線

| 如果你想... | 直接看 |
| --- | --- |
| 先裝起來用 | [快速開始](#快速開始) |
| 瞭解啟動台和歷史資產 | [糾錯、OCR 和 Agent 工作流](#糾錯ocr-和-agent-工作流) |
| 瞭解語音模型 | [語音輸入與識別模型](#語音輸入與識別模型) |
| 瞭解 OCR、翻譯、總結和 Agent | [糾錯、OCR 和 Agent 工作流](#糾錯ocr-和-agent-工作流) |
| 確認數據會去哪 | [隱私說明](#隱私說明) |
| 瞭解技術棧和開源依賴 | [技術棧與開源依賴](#技術棧與開源依賴) |
| 從源碼開發 | [從源碼運行](#從源碼運行) |

## 語音輸入與識別模型

### 按住說話，松開輸入

碼上寫預設使用快捷鍵觸發聽寫。按住說話時，屏幕上會出現一個輕量的轉寫浮層；松開後，最終文字會自動輸入到當前光標位置。

你不需要切換應用，也不需要手動複製貼上。它就像鍵盤一樣，服務於當前正在使用的 App。

### 實時轉寫

說話過程中可以看到實時文本。短句、長段說明、中文、英文和中英混合內容都會即時顯示，方便你邊說邊確認方向。

碼上寫內置系統語音識別，也支持本地和在線 ASR Provider。系統自帶模型開箱可用；本地 Qwen3-ASR、Whisper、FunASR、SenseVoice、NVIDIA Nemotron、Parakeet、Omnilingual 等路線適合更重視離線能力、隱私和可控性的場景；在線 Groq、騰訊雲、阿里雲適合不想下載本地模型或需要雲端能力的場景。模型頁會明確標注“離線 / 在線”“流式 / 非流式”“中文 / 英文 / 多語言”等標籤。

### 支持的語音模型

碼上寫不會把所有模型強行塞進同一個運行時。不同模型的上游格式、流式能力、語言覆蓋和隱私邊界不同，所以會按模型選擇最合適的 Provider target 或雲端 runtime。

#### 離線 / 本地模型

這些 Provider 的音頻不上傳到第三方雲服務；除“系統自帶”可能依賴 Apple 系統服務外，本地模型都在本機完成推理。

| 模型 | 狀態 | 流式能力 | 運行路線 | 語言側重 | 適合場景 |
| --- | --- | --- | --- | --- | --- |
| 系統自帶 | 開箱可用 | 流式 | Apple Speech / SFSpeechRecognizer | 取決於 macOS 語音識別語言 | 不下載模型、先快速開始 |
| Qwen3-ASR 0.6B | 已支持 | 流式 partial + final | speech-swift `Qwen3ASR` / MLX 4bit | 中文、英文、多語言 | 預設推薦本地聽寫，體積和速度更均衡 |
| Qwen3-ASR 1.7B | 已支持 | 流式 partial + final | speech-swift `Qwen3ASR` / MLX 8bit | 中文、英文、多語言 | 更高準確率本地聽寫，需要更高內存 |
| FunASR Nano INT8 / FP32 | 已支持 | 流式片段確認 | Sherpa-ONNX | 中文、英文 | 中文本地備選，不依賴 CoreML |
| Whisper Turbo / Large V3 | 已支持 | 非流式 | WhisperKit | 多語言 | 錄音結束後的高質量完整轉寫 |
| SenseVoice | 已支持 | 當前按非流式/短句使用 | FluidAudio / CoreML | 中文、英文、多語言 | 本地多語種短句轉寫 |
| Paraformer Large zh | 已支持 | 流式片段確認 | FluidAudio / CoreML int8 | 中文 | 中文本地轉寫 |
| NVIDIA Nemotron 0.6B | 已支持 | 原生流式 | speech-swift `NemotronStreamingASR` / CoreML | 多語言 | 本地流式轉寫候選 |
| Parakeet Streaming | 已支持 | 原生流式 | speech-swift `ParakeetStreamingASR` / CoreML | 英文和歐洲語種 | 英文低延遲聽寫 |
| Omnilingual ASR | 已支持 | 非流式 | speech-swift `OmnilingualASR` / CoreML | 超多語言 | 廣語言覆蓋、文件/實驗場景 |

#### 在線 / 雲端模型

在線 Provider 會把錄音傳送到對應服務商。API Key、SecretId、SecretKey 等憑據保存在本地 SQLite 設置表中，設置頁支持用“眼睛”按鈕臨時顯示或隱藏。

| Provider | 狀態 | 流式能力 | 預設模型 / 接口 | 配置項 | 適合場景 |
| --- | --- | --- | --- | --- | --- |
| Groq（免費） | 已支持 | 非流式 | OpenAI-compatible audio transcription，預設 `whisper-large-v3-turbo` | API Key、模型名 | 不下載本地模型，松開後快速返回最終文本 |
| 騰訊雲 | 已支持 | 實時流式 | 騰訊雲實時語音識別 WebSocket，預設 `16k_zh` | AppID、SecretId、SecretKey | 中文普通話實時雲端聽寫 |
| 阿里雲 | 已支持 | 實時流式 | DashScope WebSocket，預設 `fun-asr-realtime` | 百鍊 API Key | 中文和多語言實時雲端聽寫 |
| 火山雲 | 待實現 | 計劃流式 | 豆包語音大模型流式 ASR WebSocket | 待定 | 後續接入火山雲實時 ASR |
| Mistral Voxtral | 待實現 | 待定 | 官方 Voxtral 語音能力 | 待定 | 預留在線 Provider |
| AssemblyAI | 待實現 | 待定 | AssemblyAI Transcription | 待定 | 預留在線 Provider |
| ElevenLabs Scribe | 待實現 | 待定 | ElevenLabs Scribe | 待定 | 預留在線 Provider |

## 糾錯、OCR 和 Agent 工作流

### 易錯詞與可選 LLM 糾錯

語音識別在技術詞上容易出錯，例如把 Python、JSON、TypeScript 識別成諧音或拆開的詞。碼上寫可以在聽寫完成後，用你配置的 OpenAI 兼容模型做一次保守糾錯。

新版“易錯詞”是獨立一級頁面，會在 ASR final 和可選 LLM 之後做本地確定性修正；也可以從你後續手動修改的內容中學習候選規則。LLM 糾錯不會替你潤色或改寫，只修明顯聽錯的詞，你仍然掌控原文語氣和表達。

### 剪貼板 OCR、框選截圖、翻譯和總結

複製截圖後按 `⌘⇧V`，碼上寫會識別剪貼板圖片里的文字並貼上到當前光標。按 `⌘⇧A` 框選屏幕區域時，會打開結果面板，支持原圖、OCR、翻譯和總結視圖。

這個能力適合處理網頁、報錯彈窗、截圖、設計稿和聊天記錄。OCR 結果可以繼續複製、朗讀、翻譯或總結，但不會進入易錯詞的永久學習鏈路。

### 任務助手與 AI Coding 助手控制台

“任務助手”適合把當前視窗的可見上下文、OCR 文本和你的口述意圖整理成一段可複製的提示詞；它只複製結果，不自動傳送。

AI Coding 助手控制台面向本地 coding-agent 終端。開啓後，你可以按住語音快捷鍵說出任務助手名稱和指令，碼上寫會解析目標 Agent、展示確認狀態，並把指令投遞到對應的 Codex、Claude、CodeBuddy 或任意已註冊終端會話。

### 工作台

除了菜單欄快速輸入，碼上寫也提供完整資產工作台：

| 頁面 | 可以做什麼 |
| --- | --- |
| 首頁 | 查看歷史資產、今日新增、來源分布和可復用內容；搜尋、複製或刪除語音、截圖、錄屏和剪貼簿資產 |
| 易錯詞 | 管理本地確定性糾錯規則、候選學習、啓用狀態和最近事件 |
| 風格 | 為不同應用或場景設置輸出風格，比如原文、正式、郵件、編程說明 |
| 文件轉寫 | 導入音頻或影片，排隊轉寫，導出 txt、md、srt，或保存為筆記 |
| 筆記 | 直接錄音記筆記，也可以編輯、搜尋和回看記錄 |
| 截圖 | 瀏覽截圖和錄屏記錄，查看原圖和 OCR 文本，支持收藏、搜尋、分頁和快捷複製/刪除 |
| AI Coding 助手 | 查看已註冊 Agent 任務助手、別名、工作目錄、分支和調度記錄 |
| 設置 | 管理輸入設備、快捷鍵、模型、翻譯模型、權限、隱私和數據 |
| 幫助 | 查看權限提示、版本信息、項目鏈接和常見入口 |

## 功能亮點

- **VoxFlow Palette 啟動台**：`⌥Space` 打開 Raycast 風格入口，預設選中“最近資產”，支持上下鍵、回車和 `⌘K` 動作面板。
- **歷史資產工作台**：語音 ASR 成功結果、截圖、錄屏、剪貼簿文本/圖片/文件/鏈接/顏色統一進入資產體系，首頁按資產數量、來源分布和可復用內容展示。
- **全域聽寫**：在任意可編輯輸入框里使用，不局限於碼上寫自己的視窗。
- **不搶焦點的浮層**：聽寫時只顯示輕量浮層，不打斷當前應用。
- **多 Provider ASR**：系統語音識別開箱可用，本地 Qwen3-ASR、Whisper、FunASR、SenseVoice、NVIDIA Nemotron、Parakeet、Omnilingual 等 Provider 逐步接入統一運行時；暫不支持實時流式的 Provider 會在模型頁標注“非流式”。
- **穩定文本插入**：貼上前臨時切換輸入源，完成後恢復輸入源和剪貼板，減少 CJK 輸入法干擾。
- **輸入設備選擇**：支持選擇麥克風，長設備名會自動收納，不擠爆界面。
- **快捷鍵錄制**：在設置里直接錄制想用的觸發鍵，並配置短按行為。
- **剪貼板圖片 OCR**：複製截圖或圖片後按 `⌘⇧V`，自動識別圖片文字並貼上到當前輸入框。
- **框選截圖 OCR**：按 `⌘⇧A` 框選屏幕區域，結果面板支持查看原圖、OCR、翻譯和總結。
- **AI Coding 助手控制台**：用語音把指令投遞給本地終端里的 Codex、Claude、CodeBuddy 或其他已註冊 Agent。
- **任務助手**：結合當前視窗 OCR 上下文和口述意圖生成提示詞，只複製結果，不自動傳送。
- **OpenAI 兼容模型**：可添加、測試、編輯和刪除 Provider，LLM API Key 保存到 macOS Keychain。
- **易錯詞和上下文熱詞**：用本地規則修正常見誤識別，也可從當前視窗 OCR 提取臨時上下文詞。
- **歷史和筆記**：輸入、截圖和複製內容不只是一閃而過，後續可以搜尋、複製、整理和復用。
- **文件轉寫**：把錄音、影片、會議音頻轉成文字，適合復盤和歸檔。
- **截圖／錄屏記錄庫**：所有截圖和錄屏記錄（原圖 + OCR 文本）都可回看，支持收藏、搜尋、分頁、複製與刪除。
- **內聯截圖標注**：框選截圖支持畫筆、形狀、文字、馬賽克等標注與撤銷重做，並支持滾動長圖回看。
- **數據可控**：歷史、詞彙、設置和筆記保存在本機；是否啓用 LLM 由你決定。

## 快速開始

### 下載安裝

從 [GitHub Releases](https://github.com/xingbofeng/VoxFlow/releases/latest) 下載最新版本：

1. 打開 `VoxFlow-1.10.2-macOS.dmg`
2. 將 `VoxFlow` 拖入 `Applications` 文件夾
3. 首次啟動時，如果 macOS 提示無法驗證，請按住 Control 點擊應用，選擇“打開”

安裝後可直接打開工作台里的“截圖”頁，確認截圖／錄屏記錄與 OCR 回看是否可用。

> 如果你想體驗當前 `main` 分支上的易錯詞、AI Coding 助手 或截圖 OCR 最新實現，請從源碼運行；這些能力可能晚於最新穩定版 Release。

### 系統要求

- macOS 15 Sequoia 或更高版本
- 一台帶麥克風的 Mac

### 首次授權

碼上寫需要幾個系統權限才能正常工作：

| 權限 | 用途 | 位置 |
| --- | --- | --- |
| 輔助功能 | 監聽全域快捷鍵，並把文字輸入到當前應用 | 系統設置 -> 隱私與安全性 -> 輔助功能 |
| 麥克風 | 錄制你的聲音 | 系統設置 -> 隱私與安全性 -> 麥克風 |
| 語音識別 | 使用系統自帶語音識別模型 | 系統設置 -> 隱私與安全性 -> 語音識別 |
| 屏幕錄制 | 為“任務助手”、截圖 OCR 和錄屏功能讀取當前視窗文字與內容；截圖／錄屏記錄保存在本機便於回看 | 系統設置 -> 隱私與安全性 -> 屏幕錄制 |

如果你選擇本地 Qwen3-ASR 模型，語音識別權限不是必須的；麥克風權限仍然需要。

授權後如果快捷鍵沒有響應，退出碼上寫後重新打開即可。

### 預設快捷鍵

| 快捷鍵 | 作用 |
| --- | --- |
| `⌥Space` | 打開 VoxFlow Palette 啟動台 |
| 聽寫快捷鍵 | 按住說話，松開後輸入到當前光標位置；可在設置里修改 |
| `⌘⇧V` | 識別剪貼板圖片並貼上 OCR 文本 |
| `⌘⇧A` | 框選截圖並打開 OCR 結果面板 |
| `⌘⇧F` | 對當前選中文本打開划詞動作 HUD（翻譯 / 總結 / 任務助手 / 問 AI） |
| `⌘⇧J` | 直接翻譯當前選中文本 |
| `⌘⇧K` | 直接總結當前選中文本 |
| `⌘⇧L` | 直接把當前選中文本發給任務助手 |
| `⌘⇧P` | 直接把當前選中文本發給問 AI 聊天 HUD |

划詞動作相關快捷鍵都可以在“設置 → 划詞動作 → 啓用方式”里單獨修改或清空。

## 怎麼使用

### 語音輸入

1. 把光標放到任意輸入框。
2. 按住聽寫快捷鍵。
3. 開始說話，浮層會實時顯示識別結果。
4. 松開快捷鍵，文字會自動輸入到光標所在位置。

### 錄音記筆記

打開工作台里的“筆記”，點擊錄音按鈕即可開始記錄。說話過程中會實時轉寫，完成後可以繼續編輯，也可以在最近記錄中回看。

### 文件轉寫

打開“文件轉寫”，選擇音頻或影片文件。碼上寫會顯示任務進度，完成後可以複製、導出，或保存為筆記。

### 剪貼板圖片 OCR

複製一張截圖或圖片後，按 `⌘⇧V`。碼上寫會讀取剪貼板中的圖片，自動 OCR 識別其中的文字，並貼上到當前光標所在位置。

如果剪貼板里沒有圖片，這個快捷鍵不會啟動普通語音聽寫；它只用於剪貼板圖片 OCR 工作流。

### 框選截圖 OCR、翻譯和總結

按 `⌘⇧A` 後框選屏幕區域。碼上寫會用系統截圖讀取畫面、運行 OCR，並打開結果面板。你可以在“原圖 / OCR / 翻譯 / 總結”之間切換，也可以複製或朗讀對應內容。

翻譯模型可以使用 Apple 系統翻譯、已配置的 LLM，或本地翻譯模型；總結可以走已配置 LLM 或本地總結模型。沒有可用模型時，OCR 原文仍然可用。

### 截圖／錄屏記錄庫

每次 `⌘⇧A` 觸發的截圖或錄屏都會被保留為本地記錄，便於後續回看。你可以在工作台打開“截圖”頁面，使用關鍵詞搜尋、收藏篩選、分頁瀏覽，並複製 OCR 文本、複製原圖或刪除記錄。

圖片預覽來自本地文件，不會同步到雲端、不上傳到服務端。

### 任務助手

“任務助手”會讀取當前視窗的可見文字和可選 OCR 上下文，再結合你的語音意圖生成一段可複製提示詞。它遵守只複製、不注入、不自動傳送的邊界，適合在 ChatGPT、Claude、Codex、Cursor 等工具里整理複雜請求。

### AI Coding 助手控制台

在設置里啓用 AI Coding 助手控制台後，現有語音輸入快捷鍵可以進入調度 HUD。說出任務助手名稱和任務，例如“前端檢查按鈕狀態”，碼上寫會解析目標 Agent，必要時讓你確認候選，並把指令投遞到對應終端會話。

### 啟動台：問 AI、Quicklinks 與打開網址

`⌥Space` 打開啟動台後，除了搜尋應用、命令和資產，還可以：

- **問 AI**：輸入任意問題，選「問 AI」回車，啟動台關閉，右側 HUD 進入問 AI 聊天態。復用你已配置的 LLM Provider，支持多輪對話、流式回復和 Markdown 渲染。會話保存在內存中，重新打開問 AI 可繼續追問。未配置 Provider 時 HUD 會顯示配置提示，不發起請求。
- **Quicklinks**：內置 Google、Bing、Perplexity、GitHub、StackOverflow、YouTube、Bilibili、X、小紅書、淘寶、京東。輸入站點名、中文名或別名（如 `gh`、`tb`、`b站`）會優先匹配對應站點，回車用預設瀏覽器打開搜尋結果。
- **打開網址**：輸入完整 URL、裸域名（如 `github.com/openai/codex`）、`localhost:3000` 或 `127.0.0.1:8080` 時，第一項自動選中「打開網址」，回車用預設瀏覽器打開。裸域名會自動補 `https://`。

划詞動作面板（`⌘⇧F`）和划詞問 AI 直達快捷鍵（`⌘⇧P`）都會把選中文本送進同一個問 AI 聊天 HUD，不需要先打開啟動台。

### 讓專有名詞更准

在“易錯詞”里添加確定性糾錯規則，或啓用當前視窗 OCR 上下文增強，讓項目名、人名、產品名和技術詞作為臨時熱詞參與後續糾錯。

### 配置 LLM 糾錯

打開“設置 -> 模型”，添加 OpenAI 兼容 Provider，填寫 Base URL、Model 和 API Key。測試通過後，打開“啓用 LLM 糾錯”即可。

LLM API Key 會保存在 macOS Keychain，不會寫入普通配置文件。Groq、騰訊雲和阿里雲等雲端 ASR 憑據按當前產品設計保存在本地 SQLite 設置表中，可在模型設置里顯示、隱藏或刪除。

## 隱私說明

碼上寫的預設原則是：能留在本機的，就留在本機。

- 歷史記錄、易錯詞規則、筆記、任務和非敏感設置保存在本機。
- 截圖／錄屏記錄（原圖 + OCR 文本）本地保存，用於後續回看，不會上傳到雲端。
- 剪貼簿資產在本地保存，用於啟動台和首頁回看；噪音過濾規則會避免無意義的頻繁變更長期佔用歷史。
- 剪貼板圖片 OCR 仍可作為一次性識別入口；區域截圖（`⌘⇧A`）會保存原圖與 OCR 文本到本機以便回看。
- LLM API Key 保存到 macOS Keychain；雲端 ASR 憑據保存在本地 SQLite 設置表中。
- 系統自帶語音識別可能由 Apple 處理音頻，取決於系統能力和語言。
- 本地 Qwen3-ASR 模型下載後在本機運行。
- LLM 糾錯預設關閉；開啓後，只會把識別出的文本發到你配置的 API 服務。
- 選擇雲端 ASR 時，錄音會傳送給對應服務商；選擇本地模型時，音頻留在本機。碼上寫不會主動上傳筆記、歷史資產或剪貼簿內容。

更完整的說明見 [隱私說明](docs/PRIVACY.md)。

## 常見問題

| 問題 | 處理方式 |
| --- | --- |
| 按快捷鍵沒反應 | 檢查輔助功能權限，退出後重新打開碼上寫 |
| 浮層出現但沒有文字 | 檢查麥克風權限、語音識別權限或當前模型狀態 |
| 截圖／錄屏記錄找不到 | 去設置 → 數據與隱私 → 數據管理檢查存儲狀態；點擊“打開數據目錄”確認 `Application Support/VoxFlow/Screenshots/` 下是否有記錄文件；並確認已授權屏幕錄制 |
| 想關閉截圖標注預設工具？ | 當前版本沒有持久化“預設標注工具”開關；在截圖標注面板裡手動切換到“選擇/光標”工具即可避免預設進入標注模式。 |
| LLM 糾錯沒有生效 | 確認已在設置中啓用，並且預設 Provider 測試成功 |
| API Key 看不到明文 | 這是正常的，編輯時可點擊顯示按鈕臨時查看 |
| 想離線使用 | 下載並選擇 Qwen3-ASR 本地模型 |
| 誤刪了歷史或筆記 | 當前刪除是本地操作，請謹慎確認後再刪除 |

## 從源碼運行

如果你想自己構建：

```bash
git clone https://github.com/xingbofeng/VoxFlow.git
cd VoxFlow
make run-dev
```

常用命令：

```bash
make run-dev      # 日常開發：Debug + 本機架構，打包並啟動 .app
make run-native   # 本機架構 Release，用於接近發佈表現的本地驗證
make build        # arm64 Release，發佈/DMG 使用
make install      # 安裝到 /Applications
swift test        # 運行測試
```

## 技術棧與開源依賴

碼上寫是原生 macOS 應用，不是 Electron 殼。核心工程按 SwiftPM target 拆分，運行時盡量本地優先，雲端能力都通過用戶顯式配置的 Provider 接入。

| 模塊 | 技術棧 / 開源依賴 | 用在哪裡 |
| --- | --- | --- |
| App 殼層 | Swift 6、SwiftUI、AppKit、SwiftPM | 菜單欄 App、主工作台、設置、HUD、視窗生命週期 |
| 系統能力 | AVFoundation、Speech、Vision、Accessibility、Pasteboard | 錄音、Apple Speech、截圖/剪貼板 OCR、文本插入和當前視窗上下文 |
| 截圖採集與標注 | VoxFlowScreenshotKit、ScreenCaptureKit、CoreGraphics、Vision | 區域截圖、標注工具鏈、長圖滾動截圖、圖片預覽渲染 |
| 本地 ASR | speech-swift Qwen3ASR / Nemotron、WhisperKit、FluidAudio、Sherpa-ONNX vendor runtime | Qwen3-ASR、NVIDIA Nemotron、Whisper、SenseVoice、Paraformer、FunASR 等本地識別路線 |
| 雲端 ASR / LLM | OpenAI-compatible HTTP、Groq、騰訊雲實時 ASR、阿里雲 DashScope | 在線轉寫、LLM 糾錯、翻譯 fallback、總結和“任務助手”生成 |
| 易錯詞糾錯 | `Packages/VoxFlowVoiceCorrectionKit`，借鑒 TypeWhisper 的確定性後處理和 focused text observation 思路 | 本地規則匹配、衝突消解、自動學習候選、benchmark fixtures |
| 上下文熱詞 | `Packages/VoxFlowContextBoostKit`、Vision OCR、NaturalLanguage | 從當前視窗 OCR 文本提取臨時 Top-K 熱詞，只進入本次 prompt |
| AI Coding 助手 | Rust `agent-cli/` helper/router、JSON IPC、MCP 自報身份 | 把語音指令投遞給本地 Codex、Claude、CodeBuddy 或終端 Agent |
| 驗證工具 | XCTest、Makefile、GitHub Actions、JiWER 交叉檢查腳本 | 單元測試、發佈構建、ASR/糾錯 benchmark 和指標復核 |

關鍵引用和許可說明集中在對應目錄內：`Packages/VoxFlowVoiceCorrectionKit/NOTICE.md`、`SOURCE_ATTRIBUTION.md`、`MODIFICATIONS.md` 記錄 TypeWhisper 相關來源與改寫邊界；`Vendor/` 保存打包所需的本地 runtime/vendor 資源；AI Coding 助手 只維護 Rust helper，不再分發舊 Python CLI。

### 源碼目錄分層

```
Sources/                         # Swift 應用源碼、領域模塊、ASR Provider、文本插入等 SwiftPM targets
Packages/VoxFlowVoiceCorrectionKit/ # 易錯詞糾錯引擎、benchmark fixtures 和獨立測試
agent-cli/                       # AI Coding 助手 的 Rust helper/router 源碼，產物為 bundled `voxflow` 和 `vox` shim
Tests/                           # Swift 單元測試，以及 ASR benchmark Python 測試
Resources/                       # App 圖標等資源
Vendor/                          # 打包所需的本地 runtime/vendor 資源
docs/                            # GitHub Pages 落地頁、隱私說明、設計文件和方案資料
scripts/                         # 構建、ASR benchmark、架構檢查等開發腳本
tools/                           # 輔助驗證工具；當前只保留易錯詞 JiWER 交叉檢查腳本，不包含 agent CLI
.github/                         # CI、Pages、Release workflow 和發佈日誌
```

AI Coding 助手 的 CLI 源碼只維護 Rust 版本：根目錄 `agent-cli/`。舊 Python 版 `vf-agent` / `agent-cli` 參考 helper 已刪除；倉庫里剩餘的 Python 文件用於 benchmark、架構檢查或易錯詞指標交叉驗證，不參與 App 運行時，也不作為用戶 CLI 分發。

## 第三方模塊與開源協議

### 開源許可證

VoxFlow 以 GPL-3.0-or-later 分發。第三方組件仍保留各自許可證和歸屬說明，詳見 `docs/third-party-licenses.md`。

### 模塊與參考來源（統一）

| 類型 | 模塊/來源 | 鏈接 | 用途 / 參考方向 |
| --- | --- | --- | --- |
| 第三方依賴 | `speech-swift`（`Qwen3ASR`、`NemotronStreamingASR`、`ParakeetStreamingASR`、`OmnilingualASR`、`Qwen3TTS`、`Qwen3Chat`、`KokoroTTS`、`MADLADTranslation`） | [GitHub](https://github.com/soniqo/speech-swift.git) | 本地 ASR、TTS、翻譯與聊天模型運行時 |
| 第三方依賴 | `WhisperKit` | [GitHub](https://github.com/argmaxinc/WhisperKit.git) | Whisper 本地轉寫 |
| 第三方依賴 | `FluidAudio` | [GitHub](https://github.com/FluidInference/FluidAudio.git) | Paraformer / SenseVoice 本地推理加速與音頻處理 |
| 第三方依賴 | `Sherpa-ONNX` | [GitHub](https://github.com/k2-fsa/sherpa-onnx.git) | FunASR 本地推理引擎 |
| 第三方依賴 | `onnxruntime`（`Vendor/CSherpaOnnx`） | [GitHub](https://github.com/microsoft/onnxruntime) | 與 Sherpa-ONNX 聯用的本地推理 runtime |
| 倉庫內組件 | `VoxFlowContextBoostKit` | [倉庫路徑](Packages/VoxFlowContextBoostKit) | OCR 上下文熱詞抽取 |
| 倉庫內組件 | `VoxFlowVoiceCorrectionKit` | [倉庫路徑](Packages/VoxFlowVoiceCorrectionKit) | 易錯詞規則與基準 |
| 倉庫內組件 | `agent-cli`（Rust） | [倉庫路徑](agent-cli) | 本地終端 AI Agent 調度入口 |
| 參考來源 | TypeWhisper | [GitHub](https://github.com/TypeWhisper/typewhisper-mac) | 易錯詞後處理與 focused observation 機制（概念借鑒，未逐字復刻） |
| 參考來源 | FlashText | [GitHub](https://github.com/vi3k6i5/flashtext) | 替換與匹配思路參考（非運行時源碼復用） |
| 參考來源 | JiWER | [GitHub](https://github.com/jitsi/jiwer) | 評測與 benchmark 交叉校驗 |
| 參考來源 | OpenAI Evals | [GitHub](https://github.com/openai/evals) | benchmark 與測試結構參考 |
| 參考來源 | LanguageTool | [GitHub](https://github.com/languagetool-org/languagetool) | 糾錯 fixture 與測試風格參考 |

### 開源許可與歸屬文件

| 路徑 | 內容 |
| --- | --- |
| `LICENSE` | 項目主許可 |
| `SOURCE_ATTRIBUTION.md` | 第三方來源與改造邊界 |
| `MODIFICATIONS.md` | 上游差異與改動說明 |
| `Packages/VoxFlowVoiceCorrectionKit/NOTICE.md` | TypeWhisper 衍生與許可說明 |
| `Vendor/` | 打包 runtime 的許可信息 |
| `Sources/` / `Packages/` 目錄內的 `Package.swift` 與 `NOTICE/LICENSE` | 各組件的依賴與許可聲明 |

## 加入微信

掃碼添加作者微信，歡迎回饋問題、交流使用體驗。

<p align="center">
  <img src="Sources/VoxFlowApp/Resources/AuthorWeChatQRCode.jpg" alt="作者微信二維碼" width="320">
</p>
