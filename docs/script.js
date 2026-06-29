const release = {
  version: "1.10.2",
  tag: "v1.10.2",
  assetName: "VoxFlow-1.10.2-macOS.dmg"
};

const releaseDownloadURL =
  `https://github.com/xingbofeng/VoxFlow/releases/download/${release.tag}/${release.assetName}`;

const storageKey = "voxflow-docs-language";
const validLanguages = ["en", "zh", "zh-Hant", "ja", "ko"];
const languageNames = {
  en: "English",
  zh: "简体中文",
  "zh-Hant": "繁體中文",
  ja: "日本語",
  ko: "한국어"
};
const languageMeta = {
  en: { htmlLang: "en" },
  zh: { htmlLang: "zh-CN" },
  "zh-Hant": { htmlLang: "zh-Hant" },
  ja: { htmlLang: "ja" },
  ko: { htmlLang: "ko" }
};

const copy = {
  en: {
    title: "VoxFlow - Voice, OCR, and local agent workflows in one workspace",
    metaDescription: "VoxFlow brings voice input, screenshot OCR, clipboard history, and local agent routing into one macOS workspace.",
    ogTitle: "VoxFlow - Voice, OCR, and local agent workflows in one workspace",
    ogDescription: "A macOS workspace for voice input, screenshot OCR, translation, asset history, and local AI assistant routing.",
    ogImage: "https://xingbofeng.github.io/VoxFlow/assets/voxflow-hero-workbench-promo-en.png",
    heroImage: "assets/voxflow-hero-workbench-promo-en.png",
    heroAlt: "VoxFlow workspace preview for voice input, screenshot OCR, translation, and asset history",
    brand: "VoxFlow",
    navFeatures: "Features",
    navWorkflow: "Workflow",
    navGuide: "Guide",
    navShortcuts: "Shortcuts",
    eyebrow: "macOS input workspace",
    headline: "Speak, capture, translate, and keep the result.",
    heroCopy: "VoxFlow stays attached to the app you are already using: voice input, screenshot OCR, translation, clipboard history, and AI assistant routing all become searchable local assets.",
    heroBadgeVoice: "Speak to write",
    heroBadgeScreenshot: "Capture text",
    heroBadgeSelection: "Process selection",
    heroBadgeAssets: "Keep assets",
    heroBadgeAgent: "Route AI",
    download: "Download for macOS",
    downloadMeta: "macOS 15+ · Apple Silicon",
    releaseNote: `${release.tag} · Free & open source`,
    capVoiceLabel: "Voice Input",
    capVoiceTitle: "Hold to speak, release to insert",
    capVoiceCopy: "No focus stealing, no auto-submit, text returns to the current cursor.",
    capOCRLabel: "Screenshot OCR",
    capOCRTitle: "Turn any screen region into text",
    capOCRCopy: "Screenshots, clipboard images, web pages, and error dialogs become usable text.",
    capTranslateLabel: "Translate & Summarize",
    capTranslateTitle: "Process selected text in place",
    capTranslateCopy: "Translate, summarize, read aloud, and copy from one result panel.",
    capAssetsLabel: "Asset History",
    capAssetsTitle: "Recover every useful input",
    capAssetsCopy: "Voice, screenshots, and clipboard content become searchable local assets.",
    workflowLabel: "Workflow",
    workflowTitle: "One input path for four everyday jobs.",
    flowDictationTitle: "Speak ideas into the current app",
    flowDictationCopy: "Hold the dictation shortcut, watch live transcription in the overlay, then release to insert while clipboard and input state recover.",
    flowScreenshotTitle: "Make screen content editable",
    flowScreenshotCopy: "Select pages, tables, errors, or meeting material, then translate, summarize, read aloud, or copy the OCR result.",
    flowAssetsTitle: "Turn temporary context into assets",
    flowAssetsCopy: "Recent voice, screenshot, and clipboard items enter the workbench with source, time, and full-text search.",
    flowAgentTitle: "Route spoken tasks to local agents",
    flowAgentCopy: "Say Codex, Claude, CodeBuddy, or a terminal session name. VoxFlow confirms the target before dispatching a copyable task.",
    guideLabel: "Guide",
    guideTitle: "Start in this order after installing.",
    guideCopy: "VoxFlow lives in the macOS menu bar. Grant permissions first, set a dictation shortcut, then use every feature around the current app and the workspace.",
    guideStep1Title: "Grant permissions",
    guideStep1Copy: "Microphone, Accessibility, Screen Recording, and Clipboard permissions enable recording, insertion, and OCR.",
    guideStep2Title: "Set a dictation shortcut",
    guideStep2Copy: "Choose a hold-to-talk shortcut, speak in any editable field, and release to insert.",
    guideStep3Title: "Open the launcher",
    guideStep3Copy: "Use ⌥Space to view recent assets, search history, copy content, or run actions.",
    guideStep4Title: "Process screenshots and selections",
    guideStep4Copy: "Open the result panel from Screenshot OCR or selection actions, then translate, summarize, read aloud, or send to an assistant.",
    shortcutsLabel: "Shortcuts",
    shortcutsTitle: "Remember these first.",
    shortcutLauncher: "Open the workspace launcher on Recent Assets.",
    shortcutSelection: "Open the selection actions panel.",
    shortcutTranslate: "Translate selected text directly.",
    shortcutSummary: "Summarize selected text directly.",
    shortcutAgent: "Send selected text to a task assistant.",
    shortcutAskAI: "Send selected text straight to Ask AI.",
    shortcutScreenshot: "Open the area Screenshot OCR panel.",
    shortcutClipboard: "OCR a clipboard image and insert the result.",
    shortcutDictationKey: "Dictation",
    shortcutDictation: "Configure your hold-to-speak shortcut in Settings.",
    privacyLabel: "Local-first",
    privacyTitle: "Your workspace returns exactly as it was.",
    privacyCopy: "Asset history is stored locally by default. Local models keep audio on-device; content is sent out only when you choose a cloud ASR or external model provider.",
    ctaTitle: "Send the next sentence, screenshot, or translation into the workspace.",
    footerBrand: "VoxFlow © 2026",
    footer: "Swift & AppKit · Open source"
  },
  zh: {
    title: "码上写 VoxFlow - 语音、OCR 和本地 Agent 工作流都进工作台",
    metaDescription: "码上写 VoxFlow 把语音输入、截图 OCR、剪贴板历史和本地 Agent 调度收进同一个 macOS 工作台。",
    ogTitle: "码上写 VoxFlow - 语音、OCR 和本地 Agent 工作流都进工作台",
    ogDescription: "把语音输入、截图 OCR、翻译总结、剪贴板和 AI 助手调度收进同一个 macOS 工作台。",
    ogImage: "https://xingbofeng.github.io/VoxFlow/assets/voxflow-hero-workbench-promo-zh.png",
    heroImage: "assets/voxflow-hero-workbench-promo-zh.png",
    heroAlt: "码上写 VoxFlow 语音、截图 OCR、翻译和历史资产工作台预览",
    brand: "码上写 <small>VoxFlow</small>",
    navFeatures: "功能",
    navWorkflow: "工作流",
    navGuide: "使用文档",
    navShortcuts: "快捷键",
    eyebrow: "macOS 输入工作台",
    headline: "说出来、截下来、翻译好，全部沉淀成资产。",
    heroCopy: "VoxFlow 贴着当前应用工作：语音输入、截图 OCR、划词翻译、剪贴板和 AI 助手调度，都会进入一个可搜索、可复用的本地工作台。",
    heroBadgeVoice: "说话写入",
    heroBadgeScreenshot: "截图识别",
    heroBadgeSelection: "划词处理",
    heroBadgeAssets: "资产沉淀",
    heroBadgeAgent: "AI 调度",
    download: "下载 macOS App",
    downloadMeta: "macOS 15+ · Apple Silicon",
    releaseNote: `${release.tag} · 免费开源`,
    capVoiceLabel: "语音输入",
    capVoiceTitle: "按住说话，松开回填",
    capVoiceCopy: "不跳窗口，不自动发送，文本回到当前光标。",
    capOCRLabel: "截图 OCR",
    capOCRTitle: "框选任意区域提取文字",
    capOCRCopy: "截图、剪贴板图片、网页和错误弹窗都能变成文本。",
    capTranslateLabel: "翻译总结",
    capTranslateTitle: "选中文本继续处理",
    capTranslateCopy: "翻译、总结、朗读和复制在同一个结果面板完成。",
    capAssetsLabel: "历史资产",
    capAssetsTitle: "每次输入都能找回",
    capAssetsCopy: "语音、截图和剪贴板会沉淀为本地可搜索资产。",
    workflowLabel: "工作流",
    workflowTitle: "一条输入路径，覆盖四种高频场景。",
    flowDictationTitle: "把想法说进当前应用",
    flowDictationCopy: "按住听写热键，VoxFlow 在浮层里显示实时转写；松开后写回当前输入框，剪贴板和输入法状态会恢复。",
    flowScreenshotTitle: "把屏幕内容变成文本",
    flowScreenshotCopy: "框选页面、表格、报错或会议材料，OCR 后可以立即翻译、总结、朗读或复制。",
    flowAssetsTitle: "把临时内容沉淀成资产",
    flowAssetsCopy: "最近语音、截图和剪贴板会进入工作台，按来源、时间和全文检索，随时再次复用。",
    flowAgentTitle: "把任务说给本地 Agent",
    flowAgentCopy: "说出 Codex、Claude、CodeBuddy 或终端会话名称，VoxFlow 先确认目标，再投递可复制的任务指令。",
    guideLabel: "使用文档",
    guideTitle: "安装后按这个顺序开始。",
    guideCopy: "VoxFlow 是菜单栏应用。第一次打开先补齐 macOS 权限，再设置听写热键；之后所有能力都围绕当前应用和工作台展开。",
    guideStep1Title: "授权权限",
    guideStep1Copy: "麦克风、辅助功能、屏幕录制和剪贴板权限用于录音、写回和截图识别。",
    guideStep2Title: "设置听写热键",
    guideStep2Copy: "选择一个按住触发的快捷键，在任意输入框里说话并松开回填。",
    guideStep3Title: "打开启动台",
    guideStep3Copy: "用 ⌥Space 查看最近资产、搜索历史、复制内容或执行动作。",
    guideStep4Title: "处理截图和选中文本",
    guideStep4Copy: "用截图 OCR 或划词动作打开结果面板，再翻译、总结、朗读或发送给任务助手。",
    shortcutsLabel: "快捷键",
    shortcutsTitle: "不用记很多，只要先记住这几组。",
    shortcutLauncher: "打开工作台启动台，默认进入最近资产。",
    shortcutSelection: "打开划词动作面板。",
    shortcutTranslate: "直接翻译选中文本。",
    shortcutSummary: "直接总结选中文本。",
    shortcutAgent: "发给任务助手。",
    shortcutAskAI: "直接发给问 AI 聊天。",
    shortcutScreenshot: "区域截图 OCR 面板。",
    shortcutClipboard: "从剪贴板图片 OCR 并插入结果。",
    shortcutDictationKey: "听写",
    shortcutDictation: "在设置里配置按住说话的热键。",
    privacyLabel: "本地优先",
    privacyTitle: "你的输入现场，结束后恢复原样。",
    privacyCopy: "资产历史默认保存在本机。选择本地模型时音频留在设备上；只有主动选择云端 ASR 或外部模型时，才会把对应内容发送给你配置的服务商。",
    ctaTitle: "让下一句话、下一张截图、下一次翻译都进入工作台。",
    footerBrand: "码上写 VoxFlow © 2026",
    footer: "Swift & AppKit · 开源"
  },
  "zh-Hant": {
    title: "碼上寫 VoxFlow - 語音、OCR 和本地 Agent 工作流都進工作台",
    metaDescription: "碼上寫 VoxFlow 把語音輸入、截圖 OCR、剪貼簿歷史和本地 Agent 調度收進同一個 macOS 工作台。",
    ogTitle: "碼上寫 VoxFlow - 語音、OCR 和本地 Agent 工作流都進工作台",
    ogDescription: "把語音輸入、截圖 OCR、翻譯摘要、剪貼簿和 AI 助手調度收進同一個 macOS 工作台。",
    ogImage: "https://xingbofeng.github.io/VoxFlow/assets/voxflow-hero-workbench-promo-zh.png",
    heroImage: "assets/voxflow-hero-workbench-promo-zh.png",
    heroAlt: "碼上寫 VoxFlow 語音、截圖 OCR、翻譯和歷史資產工作台預覽",
    brand: "碼上寫 <small>VoxFlow</small>",
    navFeatures: "功能",
    navWorkflow: "工作流",
    navGuide: "使用文件",
    navShortcuts: "快捷鍵",
    eyebrow: "macOS 輸入工作台",
    headline: "說出來、截下來、翻譯好，全部沉澱成資產。",
    heroCopy: "VoxFlow 貼著目前應用工作：語音輸入、截圖 OCR、劃詞翻譯、剪貼簿和 AI 助手調度，都會進入一個可搜尋、可重用的本地工作台。",
    heroBadgeVoice: "說話寫入",
    heroBadgeScreenshot: "截圖辨識",
    heroBadgeSelection: "劃詞處理",
    heroBadgeAssets: "資產沉澱",
    heroBadgeAgent: "AI 調度",
    download: "下載 macOS App",
    downloadMeta: "macOS 15+ · Apple Silicon",
    releaseNote: `${release.tag} · 免費開源`,
    capVoiceLabel: "語音輸入",
    capVoiceTitle: "按住說話，放開回填",
    capVoiceCopy: "不跳視窗，不自動送出，文字回到目前游標。",
    capOCRLabel: "截圖 OCR",
    capOCRTitle: "框選任意區域擷取文字",
    capOCRCopy: "截圖、剪貼簿圖片、網頁和錯誤彈窗都能變成文字。",
    capTranslateLabel: "翻譯摘要",
    capTranslateTitle: "選中文本後繼續處理",
    capTranslateCopy: "翻譯、摘要、朗讀和複製都在同一個結果面板完成。",
    capAssetsLabel: "歷史資產",
    capAssetsTitle: "每次輸入都能找回",
    capAssetsCopy: "語音、截圖和剪貼簿會沉澱為本地可搜尋資產。",
    workflowLabel: "工作流",
    workflowTitle: "一條輸入路徑，覆蓋四種高頻場景。",
    flowDictationTitle: "把想法說進目前應用",
    flowDictationCopy: "按住聽寫熱鍵，VoxFlow 在浮層裡顯示即時轉寫；放開後寫回目前輸入框，剪貼簿和輸入法狀態也會恢復。",
    flowScreenshotTitle: "把螢幕內容變成文字",
    flowScreenshotCopy: "框選頁面、表格、錯誤訊息或會議材料，OCR 後可以立刻翻譯、摘要、朗讀或複製。",
    flowAssetsTitle: "把臨時內容沉澱成資產",
    flowAssetsCopy: "最近語音、截圖和剪貼簿會進入工作台，依來源、時間和全文檢索，隨時再次重用。",
    flowAgentTitle: "把任務說給本地 Agent",
    flowAgentCopy: "說出 Codex、Claude、CodeBuddy 或終端會話名稱，VoxFlow 先確認目標，再投遞可複製的任務指令。",
    guideLabel: "使用文件",
    guideTitle: "安裝後照這個順序開始。",
    guideCopy: "VoxFlow 是選單列應用。第一次打開先補齊 macOS 權限，再設定聽寫熱鍵；之後所有能力都圍繞目前應用和工作台展開。",
    guideStep1Title: "授權權限",
    guideStep1Copy: "麥克風、輔助功能、螢幕錄製和剪貼簿權限用於錄音、回填和截圖辨識。",
    guideStep2Title: "設定聽寫熱鍵",
    guideStep2Copy: "選一個按住觸發的快捷鍵，在任意輸入框裡說話並放開回填。",
    guideStep3Title: "打開啟動台",
    guideStep3Copy: "用 ⌥Space 查看最近資產、搜尋歷史、複製內容或執行動作。",
    guideStep4Title: "處理截圖和選中文本",
    guideStep4Copy: "用截圖 OCR 或劃詞動作打開結果面板，再翻譯、摘要、朗讀或送給任務助手。",
    shortcutsLabel: "快捷鍵",
    shortcutsTitle: "不用記很多，先記住這幾組就夠了。",
    shortcutLauncher: "打開工作台啟動台，預設進入最近資產。",
    shortcutSelection: "打開劃詞動作面板。",
    shortcutTranslate: "直接翻譯選中文本。",
    shortcutSummary: "直接摘要選中文本。",
    shortcutAgent: "送給任務助手。",
    shortcutAskAI: "直接送給問 AI 聊天。",
    shortcutScreenshot: "區域截圖 OCR 面板。",
    shortcutClipboard: "從剪貼簿圖片 OCR 並插入結果。",
    shortcutDictationKey: "聽寫",
    shortcutDictation: "在設定裡配置按住說話的熱鍵。",
    privacyLabel: "本地優先",
    privacyTitle: "你的輸入現場，結束後恢復原樣。",
    privacyCopy: "資產歷史預設保存在本機。選擇本地模型時音訊留在裝置上；只有主動選擇雲端 ASR 或外部模型時，才會把對應內容送到你配置的服務商。",
    ctaTitle: "讓下一句話、下一張截圖、下一次翻譯都進入工作台。",
    footerBrand: "碼上寫 VoxFlow © 2026",
    footer: "Swift & AppKit · 開源"
  },
  ja: {
    title: "VoxFlow - 音声入力、OCR、ローカル Agent ワークフローを 1 つのワークスペースへ",
    metaDescription: "VoxFlow は音声入力、スクリーンショット OCR、クリップボード履歴、ローカル Agent 連携を 1 つの macOS ワークスペースにまとめます。",
    ogTitle: "VoxFlow - 音声入力、OCR、ローカル Agent ワークフローを 1 つのワークスペースへ",
    ogDescription: "音声入力、スクリーンショット OCR、翻訳、履歴、ローカル AI アシスタント連携のための macOS ワークスペース。",
    ogImage: "https://xingbofeng.github.io/VoxFlow/assets/voxflow-hero-workbench-promo-en.png",
    heroImage: "assets/voxflow-hero-workbench-promo-en.png",
    heroAlt: "VoxFlow workspace preview for voice input, screenshot OCR, translation, and asset history",
    brand: "VoxFlow",
    navFeatures: "機能",
    navWorkflow: "ワークフロー",
    navGuide: "ガイド",
    navShortcuts: "ショートカット",
    eyebrow: "macOS 入力ワークスペース",
    headline: "話す、切り取る、翻訳する。結果はそのまま残せる。",
    heroCopy: "VoxFlow は今使っているアプリのそばで動きます。音声入力、スクリーンショット OCR、翻訳、クリップボード履歴、AI アシスタントの振り分けが、検索できるローカル資産になります。",
    heroBadgeVoice: "話して入力",
    heroBadgeScreenshot: "画面から文字",
    heroBadgeSelection: "選択を処理",
    heroBadgeAssets: "履歴を残す",
    heroBadgeAgent: "AI を振り分け",
    download: "macOS 版をダウンロード",
    downloadMeta: "macOS 15+ · Apple Silicon",
    releaseNote: `${release.tag} · Free & open source`,
    capVoiceLabel: "音声入力",
    capVoiceTitle: "押して話し、離して挿入",
    capVoiceCopy: "フォーカスを奪わず、自動送信もせず、文字は現在のカーソルに戻ります。",
    capOCRLabel: "スクリーンショット OCR",
    capOCRTitle: "任意の画面領域をテキスト化",
    capOCRCopy: "スクリーンショット、クリップボード画像、Web ページ、エラーダイアログをそのまま使えるテキストにします。",
    capTranslateLabel: "翻訳と要約",
    capTranslateTitle: "選択したテキストをその場で処理",
    capTranslateCopy: "翻訳、要約、読み上げ、コピーを 1 つの結果パネルで行えます。",
    capAssetsLabel: "資産履歴",
    capAssetsTitle: "使った入力をあとで拾える",
    capAssetsCopy: "音声、スクリーンショット、クリップボード内容が検索可能なローカル資産として残ります。",
    workflowLabel: "ワークフロー",
    workflowTitle: "1 本の入力導線で、よくある 4 つの作業をまかなう。",
    flowDictationTitle: "今のアプリにそのまま話しかける",
    flowDictationCopy: "音声入力ショートカットを押している間はオーバーレイにリアルタイム転写を表示し、離すとクリップボードや入力状態を戻したうえで挿入します。",
    flowScreenshotTitle: "画面の内容を編集できる文字にする",
    flowScreenshotCopy: "ページ、表、エラー、会議資料を囲めば、OCR の結果をすぐ翻訳、要約、読み上げ、コピーできます。",
    flowAssetsTitle: "一時的な文脈を資産として残す",
    flowAssetsCopy: "最近の音声、スクリーンショット、クリップボード項目は、ソース・時間・全文検索付きでワークベンチに入ります。",
    flowAgentTitle: "話したタスクをローカル Agent に渡す",
    flowAgentCopy: "Codex、Claude、CodeBuddy、またはターミナルセッション名を言うと、VoxFlow が宛先を確認してからコピー可能なタスクを送ります。",
    guideLabel: "ガイド",
    guideTitle: "インストール後はこの順番で始めてください。",
    guideCopy: "VoxFlow は macOS のメニューバーに常駐します。まず権限を付与し、音声入力ショートカットを設定してから、現在のアプリとワークスペースを中心に使います。",
    guideStep1Title: "権限を付与",
    guideStep1Copy: "マイク、アクセシビリティ、画面収録、クリップボード権限で録音、挿入、OCR を有効にします。",
    guideStep2Title: "音声入力ショートカットを設定",
    guideStep2Copy: "押して話すショートカットを選び、任意の入力欄で話して、離して挿入します。",
    guideStep3Title: "ランチャーを開く",
    guideStep3Copy: "⌥Space で最近の資産、履歴検索、コピー、各種アクションにアクセスできます。",
    guideStep4Title: "スクリーンショットと選択テキストを処理",
    guideStep4Copy: "スクリーンショット OCR や選択アクションから結果パネルを開き、翻訳、要約、読み上げ、アシスタント送信を行います。",
    shortcutsLabel: "ショートカット",
    shortcutsTitle: "まずはこのあたりを覚えれば十分です。",
    shortcutLauncher: "Recent Assets を起点にワークスペースランチャーを開く。",
    shortcutSelection: "選択アクションパネルを開く。",
    shortcutTranslate: "選択テキストを直接翻訳。",
    shortcutSummary: "選択テキストを直接要約。",
    shortcutAgent: "選択テキストをタスクアシスタントへ送る。",
    shortcutAskAI: "選択テキストを Ask AI に直接送る。",
    shortcutScreenshot: "範囲指定スクリーンショット OCR パネルを開く。",
    shortcutClipboard: "クリップボード画像を OCR して挿入。",
    shortcutDictationKey: "音声入力",
    shortcutDictation: "Settings で押して話すショートカットを設定します。",
    privacyLabel: "ローカルファースト",
    privacyTitle: "作業中の状態を変えずに戻せる。",
    privacyCopy: "資産履歴は標準でローカル保存されます。ローカルモデル利用時は音声が端末外へ出ません。クラウド ASR や外部モデルを選んだ場合だけ、そのサービスに送信されます。",
    ctaTitle: "次のひと言も、次のスクリーンショットも、次の翻訳もワークスペースへ。",
    footerBrand: "VoxFlow © 2026",
    footer: "Swift & AppKit · Open source"
  },
  ko: {
    title: "VoxFlow - 음성 입력, OCR, 로컬 Agent 워크플로를 하나의 워크스페이스로",
    metaDescription: "VoxFlow는 음성 입력, 스크린샷 OCR, 클립보드 기록, 로컬 Agent 라우팅을 하나의 macOS 워크스페이스로 묶습니다.",
    ogTitle: "VoxFlow - 음성 입력, OCR, 로컬 Agent 워크플로를 하나의 워크스페이스로",
    ogDescription: "음성 입력, 스크린샷 OCR, 번역, 기록, 로컬 AI 도우미 라우팅을 위한 macOS 워크스페이스.",
    ogImage: "https://xingbofeng.github.io/VoxFlow/assets/voxflow-hero-workbench-promo-en.png",
    heroImage: "assets/voxflow-hero-workbench-promo-en.png",
    heroAlt: "VoxFlow workspace preview for voice input, screenshot OCR, translation, and asset history",
    brand: "VoxFlow",
    navFeatures: "기능",
    navWorkflow: "워크플로",
    navGuide: "가이드",
    navShortcuts: "단축키",
    eyebrow: "macOS 입력 워크스페이스",
    headline: "말하고, 캡처하고, 번역한 다음 그대로 남겨두세요.",
    heroCopy: "VoxFlow는 지금 쓰고 있는 앱 옆에서 동작합니다. 음성 입력, 스크린샷 OCR, 번역, 클립보드 기록, AI 도우미 라우팅이 모두 검색 가능한 로컬 자산이 됩니다.",
    heroBadgeVoice: "말해서 입력",
    heroBadgeScreenshot: "화면에서 텍스트",
    heroBadgeSelection: "선택 내용 처리",
    heroBadgeAssets: "기록 보관",
    heroBadgeAgent: "AI 라우팅",
    download: "macOS용 다운로드",
    downloadMeta: "macOS 15+ · Apple Silicon",
    releaseNote: `${release.tag} · Free & open source`,
    capVoiceLabel: "음성 입력",
    capVoiceTitle: "누르고 말하고, 떼면 삽입",
    capVoiceCopy: "포커스를 빼앗지 않고, 자동 전송도 하지 않으며, 텍스트는 현재 커서로 돌아갑니다.",
    capOCRLabel: "스크린샷 OCR",
    capOCRTitle: "화면 영역을 바로 텍스트로",
    capOCRCopy: "스크린샷, 클립보드 이미지, 웹 페이지, 오류 대화상자를 바로 쓸 수 있는 텍스트로 바꿉니다.",
    capTranslateLabel: "번역과 요약",
    capTranslateTitle: "선택한 텍스트를 그 자리에서 처리",
    capTranslateCopy: "번역, 요약, 읽어주기, 복사를 하나의 결과 패널에서 처리합니다.",
    capAssetsLabel: "자산 기록",
    capAssetsTitle: "유용한 입력을 다시 꺼낼 수 있음",
    capAssetsCopy: "음성, 스크린샷, 클립보드 내용이 검색 가능한 로컬 자산으로 남습니다.",
    workflowLabel: "워크플로",
    workflowTitle: "하나의 입력 경로로 자주 쓰는 네 가지 작업을 처리합니다.",
    flowDictationTitle: "현재 앱에 바로 말하기",
    flowDictationCopy: "음성 입력 단축키를 누르는 동안 오버레이에 실시간 전사가 보이고, 손을 떼면 클립보드와 입력 상태를 복원한 뒤 삽입합니다.",
    flowScreenshotTitle: "화면 내용을 편집 가능한 텍스트로 만들기",
    flowScreenshotCopy: "페이지, 표, 오류, 회의 자료를 영역 선택하면 OCR 결과를 바로 번역, 요약, 읽어주기, 복사할 수 있습니다.",
    flowAssetsTitle: "임시 맥락을 자산으로 남기기",
    flowAssetsCopy: "최근 음성, 스크린샷, 클립보드 항목이 출처, 시간, 전문 검색과 함께 워크벤치에 들어옵니다.",
    flowAgentTitle: "말한 작업을 로컬 Agent로 보내기",
    flowAgentCopy: "Codex, Claude, CodeBuddy, 또는 터미널 세션 이름을 말하면, VoxFlow가 대상을 확인한 뒤 복사 가능한 작업을 전달합니다.",
    guideLabel: "가이드",
    guideTitle: "설치 후에는 이 순서로 시작하세요.",
    guideCopy: "VoxFlow는 macOS 메뉴 막대 앱입니다. 먼저 권한을 허용하고, 음성 입력 단축키를 설정한 다음, 현재 앱과 워크스페이스 중심으로 사용하면 됩니다.",
    guideStep1Title: "권한 허용",
    guideStep1Copy: "마이크, 손쉬운 사용, 화면 기록, 클립보드 권한이 녹음, 삽입, OCR에 필요합니다.",
    guideStep2Title: "음성 입력 단축키 설정",
    guideStep2Copy: "눌러서 말하는 단축키를 정하고, 아무 입력창에서 말한 뒤 손을 떼어 삽입합니다.",
    guideStep3Title: "런처 열기",
    guideStep3Copy: "⌥Space로 최근 자산, 기록 검색, 복사, 각종 작업에 접근할 수 있습니다.",
    guideStep4Title: "스크린샷과 선택 텍스트 처리",
    guideStep4Copy: "스크린샷 OCR이나 선택 작업에서 결과 패널을 열고, 번역, 요약, 읽어주기, 도우미 전송을 진행합니다.",
    shortcutsLabel: "단축키",
    shortcutsTitle: "우선 이것들만 기억하면 됩니다.",
    shortcutLauncher: "Recent Assets에서 시작하는 워크스페이스 런처 열기.",
    shortcutSelection: "선택 작업 패널 열기.",
    shortcutTranslate: "선택한 텍스트 바로 번역.",
    shortcutSummary: "선택한 텍스트 바로 요약.",
    shortcutAgent: "선택한 텍스트를 작업 도우미로 보내기.",
    shortcutAskAI: "선택한 텍스트를 Ask AI로 바로 보내기.",
    shortcutScreenshot: "영역 스크린샷 OCR 패널 열기.",
    shortcutClipboard: "클립보드 이미지를 OCR해서 삽입.",
    shortcutDictationKey: "음성 입력",
    shortcutDictation: "Settings에서 눌러서 말하는 단축키를 설정합니다.",
    privacyLabel: "로컬 우선",
    privacyTitle: "작업 상태를 그대로 돌려놓습니다.",
    privacyCopy: "자산 기록은 기본적으로 로컬에 저장됩니다. 로컬 모델을 쓰면 오디오는 기기 안에 머뭅니다. 클라우드 ASR이나 외부 모델을 고를 때만 해당 서비스로 전송됩니다.",
    ctaTitle: "다음 한 문장도, 다음 스크린샷도, 다음 번역도 워크스페이스로 보내세요.",
    footerBrand: "VoxFlow © 2026",
    footer: "Swift & AppKit · Open source"
  }
};

const languageSwitcher = document.querySelector("[data-language-switcher]");
const languageSwitchButton = languageSwitcher?.querySelector("[data-language-switch-button]");
const languageSwitchLabel = languageSwitcher?.querySelector("[data-language-switch-label]");
const languageMenu = languageSwitcher?.querySelector("[data-language-menu]");
const languageOptions = [...document.querySelectorAll("[data-language-option]")];
const heroPreview = document.querySelector("[data-hero-preview]");

function parseLanguage(raw) {
  return validLanguages.includes(raw) ? raw : "en";
}

function getInitialLanguage() {
  const params = new URLSearchParams(window.location.search);
  const fromQuery = parseLanguage(params.get("lang"));
  if (params.has("lang")) return fromQuery;
  return parseLanguage(window.localStorage.getItem(storageKey));
}

function writeLanguageToURL(language, { replace = false } = {}) {
  const params = new URLSearchParams(window.location.search);
  params.set("lang", language);
  params.delete("tab");
  const query = params.toString();
  const nextURL = `${window.location.pathname}${query ? `?${query}` : ""}${window.location.hash || ""}`;
  if (replace) {
    history.replaceState({ language }, "", nextURL);
  } else {
    history.pushState({ language }, "", nextURL);
  }
}

function setMeta(selector, value) {
  const element = document.querySelector(selector);
  if (element) element.setAttribute("content", value);
}

function setLanguageSwitcherState(language) {
  if (languageSwitchLabel) {
    languageSwitchLabel.textContent = languageNames[language] || languageNames.en;
  }

  languageOptions.forEach((option) => {
    const isSelected = option.dataset.languageOption === language;
    option.setAttribute("aria-checked", String(isSelected));
  });
}

function closeLanguageMenu({ focusButton = false } = {}) {
  if (languageMenu) {
    languageMenu.hidden = true;
  }
  if (languageSwitchButton) {
    languageSwitchButton.setAttribute("aria-expanded", "false");
    if (focusButton) {
      languageSwitchButton.focus();
    }
  }
}

function openLanguageMenu({ focusSelected = false } = {}) {
  if (!languageMenu || !languageSwitchButton) return;
  languageMenu.hidden = false;
  languageSwitchButton.setAttribute("aria-expanded", "true");

  if (focusSelected) {
    const selected = languageOptions.find((option) => option.getAttribute("aria-checked") === "true");
    (selected || languageOptions[0])?.focus();
  }
}

function toggleLanguageMenu() {
  if (!languageMenu || !languageSwitchButton) return;
  if (languageMenu.hidden) {
    openLanguageMenu({ focusSelected: true });
  } else {
    closeLanguageMenu({ focusButton: false });
  }
}

function setLanguage(language, { pushState = true, persist = true } = {}) {
  const selected = copy[language] || copy.en;
  const meta = languageMeta[language] || languageMeta.en;

  document.documentElement.lang = meta.htmlLang;
  document.title = selected.title;
  setMeta('meta[name="description"]', selected.metaDescription);
  setMeta('meta[property="og:title"]', selected.ogTitle);
  setMeta('meta[property="og:description"]', selected.ogDescription);
  setMeta('meta[property="og:image"]', selected.ogImage);

  document.querySelectorAll("[data-i18n]").forEach((element) => {
    const value = selected[element.dataset.i18n];
    if (value) element.innerHTML = value;
  });

  if (heroPreview) {
    heroPreview.src = selected.heroImage;
    heroPreview.alt = selected.heroAlt;
  }

  setLanguageSwitcherState(language);

  if (persist) {
    window.localStorage.setItem(storageKey, language);
  }
  if (pushState) {
    writeLanguageToURL(language);
  }
}

document.querySelectorAll("[data-download-link]").forEach((element) => {
  element.href = releaseDownloadURL;
});

if (languageSwitchButton && languageMenu) {
  languageSwitchButton.addEventListener("click", (event) => {
    event.preventDefault();
    toggleLanguageMenu();
  });

  languageSwitchButton.addEventListener("keydown", (event) => {
    if (event.key === "ArrowDown" || event.key === "Enter" || event.key === " ") {
      event.preventDefault();
      openLanguageMenu({ focusSelected: true });
    } else if (event.key === "Escape") {
      closeLanguageMenu({ focusButton: false });
    }
  });

  languageMenu.addEventListener("click", (event) => {
    const option = event.target.closest("[data-language-option]");
    if (!option) return;
    setLanguage(option.dataset.languageOption);
    closeLanguageMenu({ focusButton: true });
  });

  languageMenu.addEventListener("keydown", (event) => {
    const currentIndex = languageOptions.findIndex((option) => option === document.activeElement);

    if (event.key === "Escape") {
      event.preventDefault();
      closeLanguageMenu({ focusButton: true });
      return;
    }

    if (event.key !== "ArrowDown" && event.key !== "ArrowUp") return;

    event.preventDefault();
    const direction = event.key === "ArrowDown" ? 1 : -1;
    const nextIndex = (currentIndex + direction + languageOptions.length) % languageOptions.length;
    languageOptions[nextIndex]?.focus();
  });

  document.addEventListener("click", (event) => {
    if (!languageSwitcher.contains(event.target)) {
      closeLanguageMenu();
    }
  });
}

window.addEventListener("popstate", () => {
  const params = new URLSearchParams(window.location.search);
  setLanguage(parseLanguage(params.get("lang")), { pushState: false, persist: true });
});

const observer = new IntersectionObserver((entries) => {
  entries.forEach((entry) => {
    if (entry.isIntersecting) {
      entry.target.classList.add("is-visible");
      observer.unobserve(entry.target);
    }
  });
}, { threshold: 0.16 });

document.querySelectorAll(".motion").forEach((element) => observer.observe(element));

const initialLanguage = getInitialLanguage();
setLanguage(initialLanguage, { pushState: false, persist: true });
writeLanguageToURL(initialLanguage, { replace: true });
