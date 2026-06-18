const release = {
  version: "1.2.0",
  tag: "v1.2.0",
  assetName: "VoxFlow-1.2.0-macOS.dmg"
};

const releaseDownloadURL =
  `https://github.com/xingbofeng/VoxFlow/releases/download/${release.tag}/${release.assetName}`;

const copy = {
  zh: {
    eyebrow: "原生 macOS 语音输入",
    headlineA: "按住右 Command，",
    headlineB: "把声音送到光标。",
    heroCopy: "常驻菜单栏的语音输入工具。说完松手，中文、英文和技术词回到当前光标。",
    download: "下载 macOS App",
    downloadMeta: "macOS 14+ · Apple Silicon + Intel",
    releaseNote: `${release.tag} · 免费开源`,
    transcript: "让声音越过键盘，直接抵达光标。",
    navHome: "首页",
    navGlossary: "词汇表",
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
    flowTitle: "没有录音按钮。<br>没有上下文切换。",
    flowCopy: "随声写常驻菜单栏，却从不占据你的注意力。它只在你按住右 Command 时出现，松手后把文字送回原来的输入现场。",
    featureNativeTitle: "HUD 有存在感，但不打断你",
    featureNativeCopy: "按住右 Command 时出现底部胶囊，波形跟随声音起伏。松手后自动收起。",
    featureLanguageTitle: "界面为回看和整理而生",
    featureLanguageCopy: "首页统计、历史搜索、笔记、词汇表和模型设置都在一个清爽窗口里，不抢当前输入焦点。",
    featureRefineTitle: "只纠错，不替你说话",
    featureRefineCopy: "可选的 OpenAI-compatible LLM 只修复明显误识别。正确的内容、语气和措辞保持原样。",
    trustLabel: "隐私",
    privacyTitle: "你的输入现场，<br>结束后恢复原样。",
    privacyCopy: "输入法临时切换后自动恢复，剪贴板所有 item 与类型完整还原。无分析、无遥测；LLM 只有在你主动开启时才接收识别后的文本。",
    ctaTitle: "让下一句话，<br>直接成为文字。",
    footer: "Swift & AppKit · 开源"
  },
  en: {
    eyebrow: "Native voice input for macOS",
    headlineA: "Hold Right Command.",
    headlineB: "Speak into any app.",
    heroCopy: "A native macOS menu-bar voice input tool. Speak, release, and send Chinese, English, and technical terms back to the current cursor.",
    download: "Download for macOS",
    downloadMeta: "macOS 14+ · Apple Silicon + Intel",
    releaseNote: `${release.tag} · Free & open source`,
    transcript: "Let your voice skip the keyboard and meet the cursor.",
    navHome: "Home",
    navGlossary: "Glossary",
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
    flowTitle: "No record button.<br>No context switching.",
    flowCopy: "VoxFlow lives in the menu bar without asking for your attention. It appears while you hold Right Command, then returns the words to the exact place you were working.",
    featureNativeTitle: "A HUD you can feel, then forget",
    featureNativeCopy: "The bottom capsule appears while you hold Right Command. The waveform breathes with your voice and leaves when you release.",
    featureLanguageTitle: "A window built for review",
    featureLanguageCopy: "Home stats, searchable history, notes, glossary, style rules, and model settings live in one quiet window without stealing the current focus.",
    featureRefineTitle: "Correction, never rewriting",
    featureRefineCopy: "Optional OpenAI-compatible refinement fixes only obvious recognition errors. Correct wording, voice, and intent remain untouched.",
    trustLabel: "Privacy",
    privacyTitle: "Your workspace returns<br>exactly as it was.",
    privacyCopy: "Input sources switch back automatically, and every clipboard item and type is restored. No analytics, no telemetry; the LLM only receives recognized text when you explicitly enable it.",
    ctaTitle: "Make your next sentence<br>appear as text.",
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
    heroPreview.src = language === "zh"
      ? "assets/voiceinput-hero-zh.png"
      : "assets/voiceinput-hero-en.png";
    heroPreview.alt = language === "zh"
      ? "随声写 VoxFlow 首页、输入活跃度和听写 HUD 预览"
      : "VoxFlow home dashboard, input activity, and dictation HUD preview";
  }
  languageButton.dataset.language = language;
  localStorage.setItem("voiceinput-language", language);
}

languageButton.addEventListener("click", () => {
  setLanguage(languageButton.dataset.language === "zh" ? "en" : "zh");
});

setLanguage(initialLanguage);
