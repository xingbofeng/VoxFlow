const release = {
  version: "1.3.0",
  tag: "v1.3.0",
  assetName: "VoxFlow-1.3.0-macOS.dmg"
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
    downloadMeta: "macOS 15+ · Apple Silicon",
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
    featureLanguageTitle: "听写之外，也能整理成稿",
    featureLanguageCopy: "历史、笔记、文件转写和剪贴板图片 OCR 都在工作台里，需要回看时再打开。",
    featureRefineTitle: "本地优先，也保留云端选择",
    featureRefineCopy: "Apple Speech 和多种本地模型可直接使用，也支持 Groq、腾讯云与阿里云；模型页清楚标注在线、离线与流式能力。",
    trustLabel: "隐私",
    privacyTitle: "你的输入现场，<br>结束后恢复原样。",
    privacyCopy: "输入法临时切换后自动恢复，剪贴板完整还原。无分析、无遥测；本地模型让音频留在设备上，只有主动选择云端 ASR 时才会把录音发送给对应服务商。",
    ctaTitle: "让下一句话，<br>直接成为文字。",
    footer: "Swift & AppKit · 开源"
  },
  en: {
    eyebrow: "Native voice input for macOS",
    headlineA: "Hold Right Command.",
    headlineB: "Speak into any app.",
    heroCopy: "A native macOS menu-bar voice input tool. Speak, release, and send Chinese, English, and technical terms back to the current cursor.",
    download: "Download for macOS",
    downloadMeta: "macOS 15+ · Apple Silicon",
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
    featureLanguageTitle: "From dictation to a useful draft",
    featureLanguageCopy: "History, notes, file transcription, and clipboard image OCR stay in the workbench until you need them.",
    featureRefineTitle: "Local first, with cloud when useful",
    featureRefineCopy: "Use Apple Speech and multiple on-device models, or choose Groq, Tencent Cloud, and Alibaba Cloud. Models clearly show online, offline, and streaming capability.",
    trustLabel: "Privacy",
    privacyTitle: "Your workspace returns<br>exactly as it was.",
    privacyCopy: "Input sources switch back automatically and the clipboard is restored. No analytics or telemetry; local models keep audio on-device, and audio leaves the Mac only when you select a cloud ASR provider.",
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
