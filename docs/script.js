const release = {
  version: "1.8.0",
  tag: "v1.8.0",
  assetName: "VoxFlow-1.8.0-macOS.dmg"
};

const releaseDownloadURL =
  `https://github.com/xingbofeng/VoxFlow/releases/download/${release.tag}/${release.assetName}`;

const copy = {
  zh: {
    title: "码上写 VoxFlow - 语音、OCR、翻译都进工作台",
    metaDescription: "码上写 VoxFlow - 把语音输入、截图 OCR、翻译总结、剪切板和 AI 助手调度收进同一个 macOS 工作台。",
    ogTitle: "码上写 VoxFlow - 语音、OCR、翻译都进工作台",
    ogDescription: "把语音输入、截图 OCR、翻译总结、剪切板和 AI 助手调度收进同一个 macOS 工作台。",
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
    heroCopy: "VoxFlow 贴着当前应用工作：语音输入、截图 OCR、划词翻译、剪切板和 AI 助手调度，都会进入一个可搜索、可复用的本地工作台。",
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
    capAssetsCopy: "语音、截图和剪切板会沉淀为本地可搜索资产。",
    workflowLabel: "工作流",
    workflowTitle: "一条输入路径，覆盖四种高频场景。",
    flowDictationTitle: "把想法说进当前应用",
    flowDictationCopy: "按住听写热键，VoxFlow 在浮层里显示实时转写；松开后写回当前输入框，剪切板和输入法状态会恢复。",
    flowScreenshotTitle: "把屏幕内容变成文本",
    flowScreenshotCopy: "框选页面、表格、报错或会议材料，OCR 后可以立即翻译、总结、朗读或复制。",
    flowAssetsTitle: "把临时内容沉淀成资产",
    flowAssetsCopy: "最近语音、截图和剪切板会进入工作台，按来源、时间和全文检索，随时再次复用。",
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
    guideStep3Copy: "用 Option + Space 查看最近资产、搜索历史、复制内容或执行动作。",
    guideStep4Title: "处理截图和选中文本",
    guideStep4Copy: "用截图 OCR 或划词动作打开结果面板，再翻译、总结、朗读或发送给任务助手。",
    shortcutsLabel: "快捷键",
    shortcutsTitle: "不用记很多，只要先记住这几组。",
    shortcutLauncher: "打开工作台启动台，默认进入最近资产。",
    shortcutSelection: "打开划词动作面板。",
    shortcutTranslate: "直接翻译选中文本。",
    shortcutSummary: "直接总结选中文本。",
    shortcutAgent: "发给任务助手。",
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
  en: {
    title: "WriteNow VoxFlow - Voice, OCR, and translation in one workspace",
    metaDescription: "WriteNow VoxFlow brings voice input, screenshot OCR, translation, clipboard history, and AI assistant routing into one macOS workspace.",
    ogTitle: "WriteNow VoxFlow - Voice, OCR, and translation in one workspace",
    ogDescription: "A macOS workspace for voice input, screenshot OCR, translation, asset history, and local AI assistant routing.",
    ogImage: "https://xingbofeng.github.io/VoxFlow/assets/voxflow-hero-workbench-promo-en.png",
    heroImage: "assets/voxflow-hero-workbench-promo-en.png",
    heroAlt: "WriteNow VoxFlow workspace preview for voice input, screenshot OCR, translation, and asset history",
    brand: "WriteNow <small>VoxFlow</small>",
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
    guideStep3Copy: "Use Option + Space to view recent assets, search history, copy content, or run actions.",
    guideStep4Title: "Process screenshots and selections",
    guideStep4Copy: "Open the result panel from Screenshot OCR or selection actions, then translate, summarize, read aloud, or send to an assistant.",
    shortcutsLabel: "Shortcuts",
    shortcutsTitle: "Remember these first.",
    shortcutLauncher: "Open the workspace launcher on Recent Assets.",
    shortcutSelection: "Open the selection actions panel.",
    shortcutTranslate: "Translate selected text directly.",
    shortcutSummary: "Summarize selected text directly.",
    shortcutAgent: "Send selected text to a task assistant.",
    shortcutScreenshot: "Open the area Screenshot OCR panel.",
    shortcutClipboard: "OCR a clipboard image and insert the result.",
    shortcutDictationKey: "Dictation",
    shortcutDictation: "Configure your hold-to-speak shortcut in Settings.",
    privacyLabel: "Local-first",
    privacyTitle: "Your workspace returns exactly as it was.",
    privacyCopy: "Asset history is stored locally by default. Local models keep audio on-device; content is sent out only when you choose a cloud ASR or external model provider.",
    ctaTitle: "Send the next sentence, screenshot, or translation into the workspace.",
    footerBrand: "WriteNow VoxFlow © 2026",
    footer: "Swift & AppKit · Open source"
  }
};

const languageButton = document.querySelector(".language-switch");
const languageLabel = document.querySelector("[data-lang-label]");
const heroPreview = document.querySelector("[data-hero-preview]");
const validLanguages = new Set(["zh", "en"]);
const defaultLanguage = navigator.language.toLowerCase().startsWith("zh") ? "zh" : "en";

function parseLanguage(raw) {
  const normalized = (raw || "").toLowerCase();
  return validLanguages.has(normalized) ? normalized : defaultLanguage;
}

function writeLanguageToURL(language, { replace = false } = {}) {
  const params = new URLSearchParams(window.location.search);
  params.set("lang", language);
  params.delete("tab");
  const nextURL = `${window.location.pathname}?${params.toString()}${window.location.hash || ""}`;
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

function setLanguage(language, shouldPushState = true) {
  const selected = copy[language];
  document.documentElement.lang = language === "zh" ? "zh-CN" : "en";
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
  languageLabel.textContent = language === "zh" ? "EN" : "ZH";
  languageButton.dataset.language = language;
  if (shouldPushState) writeLanguageToURL(language);
}

document.querySelectorAll("[data-download-link]").forEach((element) => {
  element.href = releaseDownloadURL;
});

languageButton.addEventListener("click", () => {
  setLanguage(languageButton.dataset.language === "zh" ? "en" : "zh");
});

window.addEventListener("popstate", () => {
  setLanguage(parseLanguage(new URLSearchParams(window.location.search).get("lang")), false);
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

setLanguage(parseLanguage(new URLSearchParams(window.location.search).get("lang")), false);
writeLanguageToURL(languageButton.dataset.language, { replace: true });
