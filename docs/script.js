const release = {
  version: "1.5.0",
  tag: "v1.5.0",
  assetName: "VoxFlow-1.5.0-macOS.dmg"
};

const releaseDownloadURL =
  `https://github.com/xingbofeng/VoxFlow/releases/download/${release.tag}/${release.assetName}`;

const copy = {
  zh: {
    eyebrow: "原生 macOS 语音工作流",
    headlineA: "声音、截图、指令，",
    headlineB: "回到当前现场。",
    heroCopy: "常驻菜单栏的输入层。按住说话即可写入当前光标，框选截图即可提取文字，喊出任务助手即可把任务投递给本地 Agent。",
    download: "下载 macOS App",
    downloadMeta: "macOS 15+ · Apple Silicon",
    releaseNote: `${release.tag} · 免费开源`,
    transcript: "让声音越过键盘，直接抵达光标。",
    navHome: "首页",
    navStyle: "风格",
    navFile: "文件转写",
    navNotes: "笔记",
    navSettings: "设置",
    appHomeTitle: "首页",
    metricTotal: "累计字符",
    metricToday: "今日字符",
    metricCpm: "平均 CPM",
    metricStreak: "连续使用",
    metricStreakValue: "1 天",
    goalTitle: "今日目标",
    historyTitle: "历史",
    historySearch: "搜索历史",
    historyOne: "还有就是你删除进入那里啊我不知道是什么原因啊什么一直他就在显示啊我没办法让他一直在那里显示",
    historyTwo: "把这段发到备忘录，保留中文语气。",
    flowLabel: "工作流",
    flowTitle: "不切窗口，<br>也不打断思路。",
    flowCopy: "语音输入、易错词修正、截图 OCR、任务助手和 AI Coding 助手 调度都贴着当前应用完成。码上写只在你需要它时出现，结束后把现场恢复原样。",
    featureNativeTitle: "按住说话，松开写入",
    featureNativeCopy: "底部 HUD 显示实时转写和声音状态；松手后文本回到当前光标，不抢焦点，不自动发送。",
    featureCorrectionTitle: "易错词让技术词更稳",
    featureCorrectionCopy: "ASR final 和可选 LLM 之后，本地规则会修正常见误识别；后续编辑还能沉淀成候选规则。",
    featureLanguageTitle: "截图也能变成可用文本",
    featureLanguageCopy: "剪贴板图片 OCR 直接粘贴识别结果；框选截图 OCR 打开结果面板，可继续翻译、总结或朗读。",
    featureRefineTitle: "把任务说给本地 Agent",
    featureRefineCopy: "AI Coding 助手 HUD 控制台识别任务助手、展示确认状态，并把语音指令投递给已注册的 Codex、Claude、CodeBuddy 或终端 Agent。",
    trustLabel: "隐私",
    privacyTitle: "你的输入现场，<br>结束后恢复原样。",
    privacyCopy: "输入法临时切换后自动恢复，剪贴板完整还原。截图 OCR 和任务助手的视觉上下文不保存原图；本地模型让音频留在设备上，只有主动选择云端 ASR 时才会把录音发送给对应服务商。",
    ctaTitle: "让下一句话、下一张截图、<br>下一条指令直接进入工作流。",
    footer: "Swift & AppKit · 开源"
  },
  en: {
    eyebrow: "Native voice workflow for macOS",
    headlineA: "Voice, screenshots,",
    headlineB: "and commands stay in flow.",
    heroCopy: "A menu-bar input layer for macOS. Hold to dictate into the current cursor, select screenshots for OCR, and speak tasks directly to local agents.",
    download: "Download for macOS",
    downloadMeta: "macOS 15+ · Apple Silicon",
    releaseNote: `${release.tag} · Free & open source`,
    transcript: "Let your voice skip the keyboard and meet the cursor.",
    navHome: "Home",
    navStyle: "Style",
    navFile: "Files",
    navNotes: "Notes",
    navSettings: "Settings",
    appHomeTitle: "Home",
    metricTotal: "Total chars",
    metricToday: "Today",
    metricCpm: "Avg CPM",
    metricStreak: "Streak",
    metricStreakValue: "1 day",
    goalTitle: "Today goal",
    historyTitle: "History",
    historySearch: "Search history",
    historyOne: "Send this sentence back to Codex and keep the original Chinese tone.",
    historyTwo: "Turn the meeting note into a short reminder.",
    flowLabel: "Workflow",
    flowTitle: "No window switching.<br>No broken train of thought.",
    flowCopy: "Dictation, Personal Corrections, Screenshot OCR, Agent Compose, and AI Coding 助手 stay attached to the app you are already using. VoxFlow appears only when needed and restores the workspace afterward.",
    featureNativeTitle: "Hold to speak, release to insert",
    featureNativeCopy: "The bottom HUD shows live transcription and voice activity; released text returns to the current cursor without stealing focus or auto-submitting.",
    featureCorrectionTitle: "Personal Corrections stabilize technical terms",
    featureCorrectionCopy: "After ASR final output and optional LLM correction, local rules fix common misrecognitions. Later edits can become candidate rules.",
    featureLanguageTitle: "Screenshots become usable text",
    featureLanguageCopy: "Clipboard image OCR pastes recognized text directly; screenshot OCR opens a result panel with translation, summary, and speech playback.",
    featureRefineTitle: "Speak tasks to local agents",
    featureRefineCopy: "AI Coding 助手 resolves the task assistant, shows confirmation state, and dispatches spoken instructions to registered Codex, Claude, CodeBuddy, or terminal agents.",
    trustLabel: "Privacy",
    privacyTitle: "Your workspace returns<br>exactly as it was.",
    privacyCopy: "Input sources switch back automatically and the clipboard is restored. Screenshot OCR and Agent Compose do not persist source images; local models keep audio on-device, and audio leaves the Mac only when you select a cloud ASR provider.",
    ctaTitle: "Send the next sentence,<br>screenshot, or command into flow.",
    footer: "Swift & AppKit · Open source"
  }
};

const languageButton = document.querySelector(".language-switch");
const languageLabel = document.querySelector("[data-lang-label]");
const heroPreview = document.querySelector("[data-hero-preview]");
const initialLanguage = localStorage.getItem("voiceinput-language")
  ?? (navigator.language.toLowerCase().startsWith("zh") ? "zh" : "en");

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
      ? "码上写 VoxFlow 语音、OCR、易错词和 AI Coding 助手 工作流预览"
      : "VoxFlow workflow preview for dictation, OCR, personal corrections, and AI Coding 助手";
  }
  languageButton.dataset.language = language;
  localStorage.setItem("voiceinput-language", language);
}

languageButton.addEventListener("click", () => {
  setLanguage(languageButton.dataset.language === "zh" ? "en" : "zh");
});

setLanguage(initialLanguage);
