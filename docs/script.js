const release = {
  version: "1.6.0",
  tag: "v1.6.0",
  assetName: "VoxFlow-1.6.0-macOS.dmg"
};

const releaseDownloadURL =
  `https://github.com/xingbofeng/VoxFlow/releases/download/${release.tag}/${release.assetName}`;

  const copy = {
  zh: {
    eyebrow: "macOS 资产工作台",
    headlineA: "语音、截图、剪切板，",
    headlineB: "都进同一个工作台。",
    heroCopy: "Option + Space 打开启动台，找回最近语音、截图和剪切板资产；按住说话、框选截图、复制内容都会沉淀为可搜索、可复用的本地历史。",
    download: "下载 macOS App",
    downloadMeta: "macOS 15+ · Apple Silicon",
    releaseNote: `${release.tag} · 免费开源`,
    transcript: "让每次输入都变成可找回的资产。",
  navHome: "首页",
  navStyle: "风格",
  navFile: "文件转写",
  navNotes: "笔记",
  navSettings: "设置",
  tabHome: "首页",
  tabQuickStart: "快速开始",
  tabShortcuts: "快捷键",
  quickstartLabel: "快速开始",
  quickstartTitle: "VoxFlow 快速开始",
  quickstartIntro: "一页看懂 VoxFlow 的完整使用流程：从权限、听写到任务发送，按步骤完成日常工作。",
  docShortcutTitle: "快捷键速查",
  shortcutsLabel: "快捷键",
  docShortcutIntro: "先看快捷键，先搭好习惯；你也可以在设置里改掉和恢复默认。",
  docShortcutLauncher: "打开启动台，进入最近资产视图。",
  docShortcutSelection: "划词动作（翻译/总结/发给任务助手）弹窗。",
  docShortcutTranslate: "直接执行文本翻译。",
  docShortcutSummarize: "直接执行文本总结。",
  docShortcutAgent: "直接发给任务助手。",
  docShortcutScreenshotOcr: "区域截图 OCR 面板。",
  docShortcutClipboardOcr: "从剪贴板图片 OCR 并插入结果。",
  docShortcutDictation: "在设置里设置你的听写热键。",
  docShortcutDictationKey: "听写",
  docStep1Title: "准备：安装与权限",
  docStep1Body: "第一次打开时按提示完成麦克风、辅助功能、屏幕录制和剪贴板权限。每项权限缺失都会在对应入口给出指引，补齐后重启后即可使用。",
  docStep2Title: "语音输入：快速上手",
  docStep2Body: "打开设置确认听写快捷键后按住触发键开始录音，结束后松开键，文本会自动回填到当前输入焦点。支持在输入法切换后稳定贴回，无需手动处理焦点。",
  docStep3Title: "启动台与资产回看",
  docStep3Body: "按下 Option + Space 打开启动台，最近语音 / 截图 / 剪贴板会作为首屏内容出现，可搜索、复制、删除并快速回放。",
  docStep4Title: "截图与 OCR",
  docStep4Body: "截取区域后可将图片 OCR 转成文本；在结果面板可继续进行翻译、总结、朗读。也可直接对剪贴板图片触发识别并粘贴结果。",
  docStep5Title: "划词动作与助手",
  docStep5Body: "选中文本后可通过快捷键触发动作卡（如翻译、总结、发给任务助手）。常用流程建议先打开结果再确认，避免误发。",
  docStep6Title: "文件转写与笔记",
  docStep6Body: "支持文件转写和笔记模块，转写结果会归类到资产历史，可再次搜索、复用，适合长文本复盘和会议记录整理。",
  appHomeTitle: "首页",
    metricTotal: "累计资产",
    metricToday: "今日新增",
    metricCpm: "来源分布",
    metricStreak: "可复用内容",
    metricStreakValue: "18 条",
    goalTitle: "资产活跃度",
    historyTitle: "历史资产",
    historySearch: "搜索资产",
    historyOne: "还有就是你删除进入那里啊我不知道是什么原因啊什么一直他就在显示啊我没办法让他一直在那里显示",
    historyTwo: "把这段发到备忘录，保留中文语气。",
    flowLabel: "工作流",
    flowTitle: "不切窗口，<br>也不打断思路。",
    flowCopy: "启动台、最近资产、语音输入、截图 OCR、剪切板历史和 AI Coding 助手调度都贴着当前应用完成。码上写只在你需要它时出现，结束后把现场恢复原样。",
    featureNativeTitle: "启动台先到最近资产",
    featureNativeCopy: "Option + Space 打开 Raycast 风格入口，默认选中最近资产；上下键、回车和 Command + K 都服务键盘流。",
    featureCorrectionTitle: "首页变成资产管理",
    featureCorrectionCopy: "首页展示累计资产、今日新增、来源分布和可复用内容；语音、截图、剪切板都能搜索、复制和删除。",
    featureLanguageTitle: "截图也能变成可用文本",
    featureLanguageCopy: "剪贴板图片 OCR 直接粘贴识别结果；框选截图 OCR 打开结果面板，可继续翻译、总结或朗读。",
    featureRefineTitle: "把任务说给本地 Agent",
    featureRefineCopy: "AI Coding 助手 HUD 控制台识别任务助手、展示确认状态，并把语音指令投递给已注册的 Codex、Claude、CodeBuddy 或终端 Agent。",
    trustLabel: "隐私",
  privacyTitle: "你的输入现场，<br>结束后恢复原样。",
  privacyCopy: "资产历史保存在本机，剪切板资产只用于启动台和首页回看；本地模型让音频留在设备上，只有主动选择云端 ASR 时才会把录音发送给对应服务商。",
  ctaTitle: "让下一句话、下一张截图、<br>下一次复制都进入工作台。",
  footer: "Swift & AppKit · 开源"
  },
  en: {
    eyebrow: "macOS asset workbench",
    headlineA: "Voice, screenshots,",
    headlineB: "and clipboard in one workbench.",
    heroCopy: "Press Option + Space to open the launcher and recover recent voice, screenshot, and clipboard assets. Dictation, captures, and copied content become searchable, reusable local history.",
    download: "Download for macOS",
    downloadMeta: "macOS 15+ · Apple Silicon",
    releaseNote: `${release.tag} · Free & open source`,
    transcript: "Turn each input into a reusable asset.",
    navHome: "Home",
  navStyle: "Style",
  navFile: "Files",
  navNotes: "Notes",
  navSettings: "Settings",
  tabHome: "Home",
  tabQuickStart: "Quick Start",
  tabShortcuts: "Shortcuts",
  quickstartLabel: "Quick Start",
  quickstartTitle: "VoxFlow Quick Start",
  quickstartIntro: "One page to understand VoxFlow end-to-end: from permissions and dictation to task dispatch.",
  docShortcutTitle: "Shortcuts",
  shortcutsLabel: "Shortcuts",
  docShortcutIntro: "Learn the shortcuts first, then lock the flow. You can change any shortcut in Settings and restore defaults there.",
  docShortcutLauncher: "Open launcher and jump to recent assets.",
  docShortcutSelection: "Open selection action card for translate/summarize/send to agent.",
  docShortcutTranslate: "Run direct translate for selected text.",
  docShortcutSummarize: "Run direct summarize for selected text.",
  docShortcutAgent: "Send selected text directly to task assistant.",
  docShortcutScreenshotOcr: "Open Screenshot OCR result panel for area capture.",
  docShortcutClipboardOcr: "OCR from clipboard image and paste recognized text.",
  docShortcutDictation: "Set your dictation shortcut in Settings.",
  docShortcutDictationKey: "Dictation",
  docStep1Title: "Get started: install and permissions",
  docStep1Body: "When you open the app for the first time, complete microphone, accessibility, screen recording, and clipboard permissions as prompted. Each missing permission shows the corresponding setup guide.",
    docStep2Title: "Dictation quick start",
    docStep2Body: "Set the dictation shortcut in Settings, press and hold it to record, then release to finish insertion. VoxFlow inserts the text back to the current focus and recovers context safely.",
    docStep3Title: "Launcher and history",
    docStep3Body: "Press Option + Space to open the launcher. Recent voice, screenshot, and clipboard assets are shown on the first screen, where you can search, copy, delete, or re-open items.",
    docStep4Title: "Screenshot OCR",
    docStep4Body: "After selecting an area, OCR turns images into text. The result panel also supports follow-up actions such as translation, summarization, and reading out loud. Clipboard images can be processed directly as well.",
    docStep5Title: "Selection actions and assistant",
    docStep5Body: "After selecting text, use action shortcuts (translate/summarize/send to agent) to open result flow. Confirm before dispatching to avoid sending unfinished instructions.",
    docStep6Title: "File transcription and notes",
    docStep6Body: "Transcription jobs and notes are collected into history for reuse, search, and polishing when you need to extract useful content later.",
    appHomeTitle: "Home",
    metricTotal: "Total assets",
    metricToday: "Today",
    metricCpm: "Source mix",
    metricStreak: "Reusable",
    metricStreakValue: "18 items",
    goalTitle: "Asset activity",
    historyTitle: "Asset history",
    historySearch: "Search assets",
    historyOne: "Send this sentence back to Codex and keep the original Chinese tone.",
    historyTwo: "Turn the meeting note into a short reminder.",
    flowLabel: "Workflow",
    flowTitle: "No window switching.<br>No broken train of thought.",
    flowCopy: "Launcher, Recent Assets, dictation, Screenshot OCR, clipboard history, and AI Coding 助手 stay attached to the app you are already using. VoxFlow appears only when needed and restores the workspace afterward.",
    featureNativeTitle: "Launcher opens on Recent Assets",
    featureNativeCopy: "Option + Space opens a Raycast-style launcher with Recent Assets selected by default; arrow keys, Enter, and Command + K are first-class.",
    featureCorrectionTitle: "Home becomes asset management",
    featureCorrectionCopy: "Home shows total assets, today's additions, source mix, and reusable content. Voice, screenshots, and clipboard items can be searched, copied, or deleted.",
    featureLanguageTitle: "Screenshots become usable text",
    featureLanguageCopy: "Clipboard image OCR pastes recognized text directly; screenshot OCR opens a result panel with translation, summary, and speech playback.",
    featureRefineTitle: "Speak tasks to local agents",
    featureRefineCopy: "AI Coding 助手 resolves the task assistant, shows confirmation state, and dispatches spoken instructions to registered Codex, Claude, CodeBuddy, or terminal agents.",
    trustLabel: "Privacy",
    privacyTitle: "Your workspace returns<br>exactly as it was.",
    privacyCopy: "Asset history stays local, and clipboard assets are used for launcher and Home review. Local models keep audio on-device, and audio leaves the Mac only when you select a cloud ASR provider.",
    ctaTitle: "Send the next sentence,<br>screenshot, or copy into the workbench.",
    footer: "Swift & AppKit · Open source"
  }
};

const languageButton = document.querySelector(".language-switch");
const languageLabel = document.querySelector("[data-lang-label]");
const heroPreview = document.querySelector("[data-hero-preview]");
const tabButtons = document.querySelectorAll("[data-tab-btn]");
const tabPanels = document.querySelectorAll("[data-tab-id]");
const validTabs = new Set(["landing", "quickstart", "shortcuts"]);
const initialLanguage = localStorage.getItem("voiceinput-language")
  ?? (navigator.language.toLowerCase().startsWith("zh") ? "zh" : "en");
const rawStoredTab = localStorage.getItem("voiceinput-doc-tab");
const initialTab = validTabs.has(rawStoredTab || "")
  ? rawStoredTab
  : rawStoredTab === "docs"
    ? "quickstart"
    : "landing";

function setActiveTab(tabId) {
  tabButtons.forEach((button) => {
    const isActive = button.dataset.tabBtn === tabId;
    button.classList.toggle("is-active", isActive);
    button.setAttribute("aria-selected", String(isActive));
    button.setAttribute("aria-pressed", String(isActive));
  });

  tabPanels.forEach((panel) => {
    const isActive = panel.dataset.tabId === tabId;
    panel.classList.toggle("is-active", isActive);
    panel.classList.toggle("is-hidden", !isActive);
    panel.setAttribute("aria-hidden", String(!isActive));
  });

  localStorage.setItem("voiceinput-doc-tab", tabId);
}

document.querySelectorAll("[data-download-link]").forEach((element) => {
  element.href = releaseDownloadURL;
});

function setLanguage(language) {
  const selected = copy[language];
  document.documentElement.lang = language === "zh" ? "zh-CN" : "en";
  document.querySelectorAll("[data-i18n]").forEach((element) => {
    const value = selected[element.dataset.i18n];
    if (value) element.innerHTML = value;
  });
  languageLabel.textContent = language === "zh" ? "EN" : "中";
  if (heroPreview) {
    heroPreview.alt = language === "zh"
      ? "码上写 VoxFlow 启动台、历史资产、语音、截图和 AI Coding 助手工作流预览"
      : "VoxFlow launcher and asset history preview for voice, screenshots, clipboard, and AI Coding 助手";
  }
  languageButton.dataset.language = language;
  localStorage.setItem("voiceinput-language", language);
}

languageButton.addEventListener("click", () => {
  setLanguage(languageButton.dataset.language === "zh" ? "en" : "zh");
});

tabButtons.forEach((button) => {
  button.addEventListener("click", () => {
    setActiveTab(button.dataset.tabBtn);
  });
});

setLanguage(initialLanguage);
setActiveTab(initialTab);
