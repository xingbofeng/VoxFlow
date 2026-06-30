<div align="center">
  <img src="docs/assets/voiceinput-logo.png" alt="VoxFlow logo" width="128">

  <h1>VoxFlow</h1>
  <p><strong>音声、スクリーンショット、画面収録、クリップボード履歴、coding-agent 指示のための macOS アセットワークベンチ。</strong></p>
  <p><code>⌥Space</code> でランチャーを開き、最近の音声、スクリーンショット、画面収録、クリップボード資産をすぐ呼び戻せます。音声入力、キャプチャ、収録、コピーした内容は、検索できて、コピーできて、再利用できるローカル履歴になります。</p>

  <p>
    <img src="https://img.shields.io/badge/macOS-15%2B-111827?style=flat-square&logo=apple&logoColor=white" alt="macOS 15+">
    <a href="https://github.com/xingbofeng/VoxFlow/releases/latest"><img src="https://img.shields.io/github/v/release/xingbofeng/VoxFlow?style=flat-square&label=release" alt="Latest release"></a>
    <a href="LICENSE"><img src="https://img.shields.io/badge/license-GPL--3.0--or--later-10B981?style=flat-square" alt="License: GPL-3.0-or-later"></a>
  </p>
  <p>
    🌐 <a href="https://xingbofeng.github.io/VoxFlow/">Website</a>
    &nbsp;·&nbsp;
    ⬇️ <a href="https://github.com/xingbofeng/VoxFlow/releases/latest">Download</a>
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
    <a href="docs/assets/voiceinput-demo-land.mp4"><img src="docs/assets/voiceinput-demo-land.gif" alt="Intro Video" width="100%"></a>
  </p>
</div>

## 概要

VoxFlow は、今使っているアプリに寄り添うアセットワークベンチ兼クイックランチャーです。音声アシスタントではありません。ウィンドウを奪わず、メッセージを自動送信せず、別の入力欄へ移動させません。音声、スクリーンショット、画面収録、クリップボード項目、Agent コマンドを、検索・プレビュー・再利用できるローカル資産にして、現在の作業場所へ戻します。

| やりたいこと | トリガー | 出力先 | 境界 |
| --- | --- | --- | --- |
| ランチャーを開く | `⌥Space` | Raycast 風ランチャー | 初期選択は Recent Assets。キーボード操作を優先 |
| 最近の資産を探す | Launcher -> Recent Assets | 第 2 階層の資産ブラウザ | 音声、スクリーンショット、クリップボードを共通検索・フィルタ |
| テキストを音声入力 | ショートカットを押しながら話して離す | 現在のカーソル位置 | フォーカスを奪わず、自動送信しない |
| クリップボード資産を管理 | テキスト、画像、ファイル、リンク、色をコピー | 資産履歴 | ノイズフィルタが不要な内容を保存対象から外す |
| 認識ミスを修正 | ASR final と任意の LLM 修正後に実行 | 挿入前テキスト | ローカルの決定的ルール。学習候補はユーザーが制御 |
| クリップボード画像を OCR | 画像をコピーして `⌘⇧V` | 現在のカーソル位置 | 画像専用フロー。通常の音声入力は開始しない |
| スクリーンショットや画面収録を処理 | `⌘⇧A` を押して範囲選択 | OCR 結果パネル | 翻訳、要約、読み上げは任意 |
| 選択テキストのアクション | テキストを選択し `⌘⇧F/J/K/L/P` | アクション HUD または結果パネル | F はカードを開く。J は翻訳、K は要約、L は Task Assistant、P は Ask AI |
| ランチャーから Ask AI | ランチャーに質問を入力して Ask AI を選択 | Ask AI chat HUD | 設定済み LLM provider を利用。複数ターン、ストリーミング、Markdown 対応 |
| ランチャーから Web 検索 | キーワードを入力して Quicklink を選択 | 既定ブラウザ | Google、Bing、Perplexity、GitHub、StackOverflow、YouTube、Bilibili、X、小紅書、Taobao、JD を内蔵 |
| URL を開く | URL または裸のドメインを入力 | 既定ブラウザ | http/https/裸ドメイン/localhost/IP+port を自動検出。最初の結果が Open URL |
| スクリーンショットや収録記録を見る | Workbench -> Screenshot | ローカルのスクリーンショットと収録履歴、OCR テキスト | ローカル保存。検索、お気に入り、コピー、削除に対応 |
| AI プロンプトを作る | 現在ウィンドウの文脈 + 話した意図 | コピー可能なプロンプト | コピーのみ。挿入、自動送信はしない |
| ローカル coding agent に指示 | タスクアシスタント名とタスクを話す | Codex / Claude / CodeBuddy / terminal agent session | 登録済みセッションにだけ dispatch |

## 向いている人

- ChatGPT、Claude、Codex、Cursor などの AI ツールへ、意図、文脈、修正依頼をすばやく伝えたい人。
- Codex、Claude、CodeBuddy などのターミナル Agent を同時に使い、音声で正しいローカルセッションに指示したい人。
- コードを書きながら、バグ説明、メモ、コミットメッセージ、調査記録をよく作る人。
- スクリーンショット、Web ページ、エラーダイアログ、画像から文字を取り出し、さらに翻訳や要約をしたい人。
- 中国語と英語を混ぜて話すことが多く、技術用語や製品名の誤認識を減らしたい人。

## 読み方

| 知りたいこと | 読む場所 |
| --- | --- |
| まずインストールして試す | [クイックスタート](#クイックスタート) |
| ランチャーと資産を理解する | [修正、OCR、Agent ワークフロー](#修正ocragent-ワークフロー) |
| 音声モデルを理解する | [音声入力と音声モデル](#音声入力と音声モデル) |
| OCR、翻訳、要約、Agent を理解する | [修正、OCR、Agent ワークフロー](#修正ocragent-ワークフロー) |
| データの保存先を確認する | [プライバシー](#プライバシー) |
| 技術スタックと OSS 依存を理解する | [技術スタックとオープンソース依存](#技術スタックとオープンソース依存) |
| ソースからビルドする | [ソースから実行](#ソースから実行) |

## 音声入力と音声モデル

### 押して話し、離して挿入

VoxFlow はキーボードレイヤーのように動きます。音声入力ショートカットを押しながら話し、離します。話している間は小さな文字起こしオーバーレイが表示され、最後のテキストが現在のカーソル位置に挿入されます。

アプリを切り替えたり、手動でコピーし直したりする必要はありません。

### ライブ文字起こし

話している間、認識テキストがリアルタイムに表示されるので、方向を確認しながら話せます。短いコマンド、長い説明、中国語、英語、中国語と英語の混在に対応します。

VoxFlow にはシステム音声認識に加え、ローカルとクラウドの ASR provider が含まれます。Apple Speech はそのまま使えます。Qwen3-ASR、Whisper、FunASR、SenseVoice、NVIDIA Nemotron、Parakeet、Omnilingual はローカル用途をカバーし、Groq、Tencent Cloud、Alibaba Cloud はオンライン認識を提供します。Models ページでは、ローカル/オンライン、ストリーミング対応、言語カバー範囲を明示します。

### 対応音声モデル

VoxFlow はすべてのローカルモデルを 1 つの runtime に無理に押し込みません。各 provider は、上流モデル形式とレイテンシ目標に合う経路を使います。

| Provider / Model | 現在の runtime 経路 | 推奨用途 |
| --- | --- | --- |
| Apple Speech | Apple Speech / SFSpeechRecognizer | モデルをダウンロードせずに始める標準音声入力 |
| Qwen3-ASR 0.6B | speech-swift Qwen3ASR MLX 4bit | 統一 speech-swift runtime を使う標準ローカル経路 |
| Qwen3-ASR 1.7B | speech-swift Qwen3ASR MLX 8bit | 0.6B と同じ読み込み/セッション経路を使う高精度ローカル経路 |
| Whisper Turbo / Large V3 | WhisperKit `.mlmodelc` | 録音後の高品質な全文文字起こし |
| FunASR | Sherpa-ONNX | 中国語向けローカル fallback。CoreML ではない |
| SenseVoice | FluidAudio / CoreML | ローカル多言語と短文文字起こし |
| Paraformer | FluidAudio / CoreML int8 | ローカル中国語文字起こし |
| NVIDIA Nemotron 0.6B | speech-swift NemotronStreamingASR / CoreML | ローカル多言語ストリーミング文字起こし |
| Parakeet Streaming | speech-swift ParakeetStreamingASR / CoreML | 英語と欧州言語向け低レイテンシローカルストリーミング |
| Omnilingual ASR | speech-swift OmnilingualASR / CoreML | 広い言語範囲のオフライン文字起こしと実験用途 |

クラウド provider を選ぶと、録音音声は選択したサービスに送信されます。Groq は録音後に final transcript を返し、Tencent Cloud と Alibaba Cloud はリアルタイム WebSocket 文字起こしに対応します。

| Cloud Provider | 状態 | Streaming | 既定モデル / API | 設定 |
| --- | --- | --- | --- | --- |
| Groq (Free) | 対応済み | No | `whisper-large-v3-turbo` audio transcription | API Key、model |
| Tencent Cloud | 対応済み | Yes | Realtime Speech Recognition WebSocket、`16k_zh` | AppID、SecretId、SecretKey |
| Alibaba Cloud | 対応済み | Yes | DashScope WebSocket、`fun-asr-realtime` | Bailian API Key |
| Volcengine Cloud | Planned | Planned | Doubao streaming ASR | 未定 |
| Mistral Voxtral、AssemblyAI、ElevenLabs Scribe | 未対応 | 未定 | 予約 provider | なし |

## 修正、OCR、Agent ワークフロー

### Personal Corrections と任意の LLM 修正

音声認識は Python、JSON、TypeScript、フレームワーク名、製品名などの技術用語を誤認識することがあります。VoxFlow は音声入力完了後、ユーザー自身の OpenAI 互換 provider を通して控えめな修正パスを実行できます。

新しい **Personal Corrections** ページは、ASR final output と任意の LLM 修正後に、ローカルの決定的修正を実行します。挿入後にユーザーが行った編集から候補ルールを学習することもできます。LLM パスは意図的に控えめです。文体を磨いたり言い換えたりせず、明らかな認識ミスだけを直します。

### クリップボード OCR、スクリーンショット、翻訳、要約

スクリーンショットをコピーして `⌘⇧V` を押すと、クリップボード画像を OCR し、認識テキストを現在のカーソル位置に貼り付けます。`⌘⇧A` で画面領域を選択すると、**Original Image**、**OCR**、**Translation**、**Summary** タブを持つ結果パネルが開きます。

Web ページ、エラーダイアログ、スクリーンショット、デザインモック、チャット履歴に便利です。OCR テキストはコピー、読み上げ、翻訳、要約できますが、永続的な Personal Corrections 学習ループには入りません。

### Agent Compose と AI Coding 助手 Command Center

**Agent Compose** は、現在ウィンドウの可視文脈、OCR テキスト、話した意図を組み合わせ、AI ツールへ貼り付けられるプロンプトを作ります。結果はコピーだけです。挿入、自動送信、Enter キー操作は行いません。

**AI Coding 助手 Command Center** はローカル coding-agent ターミナル向けです。有効化後、タスクアシスタント名と指示を話すと、VoxFlow が対象 Agent を解決し、確認状態を表示し、該当する Codex、Claude、CodeBuddy、または登録済みターミナルセッションに指示を送ります。

### Workbench

VoxFlow にはフル機能のアセットワークベンチもあります。

| Page | できること |
| --- | --- |
| Home | 資産履歴、今日の追加、ソース内訳、再利用可能な内容を確認。音声、スクリーンショット、画面収録、クリップボード資産を検索、コピー、削除 |
| Personal Corrections | 決定的修正ルール、学習候補、有効状態、最近のイベントを管理 |
| Styles | original、formal、email、coding notes などの出力スタイルを選択 |
| File Transcription | 音声または動画ファイルを取り込み、文字起こしし、txt/md/srt に export または notes に保存 |
| Notes | 音声メモを録音し、Markdown 編集、検索、最近のメモ確認 |
| Screenshot | OCR テキスト付きスクリーンショットと収録を閲覧。お気に入り、検索、ページング対応 |
| AI Coding 助手 | 登録済み Agent、alias、working directory、branch、dispatch log を確認 |
| Settings | 入力デバイス、ショートカット、モデル、翻訳モデル、権限、プライバシー、データを管理 |
| Help | 権限ガイド、バージョン情報、プロジェクトリンクを確認 |

## ハイライト

- **VoxFlow Palette launcher**: `⌥Space` で Raycast 風ランチャーを開きます。Recent Assets が初期選択され、矢印キー、Enter、`⌘K` アクションに対応します。
- **Asset history workbench**: ASR 成功テキスト、スクリーンショット、画面収録、クリップボードのテキスト/画像/ファイル/リンク/色が 1 つの資産システムに入ります。Home では資産数、ソース内訳、再利用可能な内容を確認できます。
- **Global dictation**: VoxFlow 内だけでなく、任意の編集可能なテキスト欄で使えます。
- **Non-intrusive overlay**: フォーカスを奪わず、ライブテキストと音声状態だけを表示します。
- **Multiple ASR providers**: 組み込みのシステム認識から始められます。ローカル Qwen3-ASR、Whisper、FunASR、SenseVoice、NVIDIA Nemotron、Parakeet、Omnilingual provider は同じ runtime model の下で統合が進んでいます。リアルタイムストリーミング非対応 provider は Models で **Non-streaming** と表示されます。
- **Stable text insertion**: 貼り付け前に一時的に入力ソースを切り替え、完了後に入力ソースとクリップボードを復元し、CJK 入力メソッドの干渉を減らします。
- **Input device selection**: マイクを選択できます。長いデバイス名も UI を崩さず扱います。
- **Shortcut recording**: 使いたいキーを録画し、短押し動作を設定できます。
- **Clipboard image OCR**: スクリーンショットや画像をコピーし、`⌘⇧V` を押すと、画像内テキストを認識して現在の入力欄に貼り付けます。
- **Screenshot OCR**: `⌘⇧A` で画面領域を選択し、Original Image、OCR text、translation、summary を結果パネルで確認できます。
- **Screenshot / recording library**: キャプチャしたスクリーンショットと収録は Screenshot ページに保存され、OCR テキスト、お気に入り、検索、ワンクリックコピー/削除に対応します。
- **Inline screenshot annotation**: 範囲キャプチャでは pen/shape/text/mosaic/scroll tool、undo/redo、最終挿入前の翻訳/要約フローを使えます。
- **AI Coding 助手 Command Center**: 音声指示を Codex、Claude、CodeBuddy、または登録済みローカル terminal agent に送れます。
- **Agent Compose**: 現在ウィンドウの OCR 文脈と話した意図からプロンプトを作ります。結果はコピーのみで、自動送信しません。
- **OpenAI-compatible providers**: provider の追加、テスト、編集、削除に対応。LLM API key は macOS Keychain に保存されます。
- **Personal corrections and context hotwords**: 繰り返しの認識ミスをローカルルールで直し、現在ウィンドウ OCR から一時的な文脈語を抽出できます。
- **History and notes**: 過去の入力、スクリーンショット、コピー内容を検索、コピー、編集、再利用できます。
- **File transcription**: 録音、動画、会議音声をテキストに変換します。
- **Local-first data**: 履歴、Personal Corrections、設定、notes、jobs はローカルに保存されます。LLM correction は opt-in です。

## クイックスタート

### ダウンロードとインストール

[GitHub Releases](https://github.com/xingbofeng/VoxFlow/releases/latest) から最新バージョンをダウンロードします。

1. `VoxFlow-1.12.0-macOS.dmg` を開く
2. `VoxFlow` を `Applications` フォルダにドラッグ
3. 初回起動時に macOS が検証できないと表示した場合は、Control キーを押しながらアプリをクリックし、**Open** を選択

インストール後、Workbench -> Screenshot を開き、スクリーンショットと収録記録、OCR 履歴が使えることを確認できます。

> Personal Corrections、AI Coding 助手、Screenshot OCR の main branch 最新実装を試す場合は、ソースから実行してください。これらの機能は最新 stable Release より新しい場合があります。

### 要件

- macOS 15 Sequoia 以降
- マイク付き Mac

### 初回権限

VoxFlow にはいくつかの macOS 権限が必要です。

| 権限 | 必要な理由 | 場所 |
| --- | --- | --- |
| Accessibility | グローバルショートカットを監視し、現在のアプリにテキストを挿入する | System Settings -> Privacy & Security -> Accessibility |
| Microphone | 音声を録音する | System Settings -> Privacy & Security -> Microphone |
| Speech Recognition | システム音声認識を使う | System Settings -> Privacy & Security -> Speech Recognition |
| Screen Recording | Agent Compose、screenshot OCR、画面収録のために現在ウィンドウを OCR する | System Settings -> Privacy & Security -> Screen Recording |

ローカル Qwen3-ASR モデルを使う場合、Speech Recognition 権限は不要です。Microphone 権限は必要です。

権限を付与してもショートカットが反応しない場合は、VoxFlow を終了して開き直してください。

### 既定ショートカット

| Shortcut | Action |
| --- | --- |
| `⌥Space` | VoxFlow Palette launcher を開く |
| Dictation shortcut | 押して話し、離すと現在のカーソルに挿入。Settings で設定可能 |
| `⌘⇧V` | クリップボード画像を OCR し、認識テキストを貼り付ける |
| `⌘⇧A` | 画面領域をキャプチャし、OCR 結果パネルを開く |
| `⌘⇧F` | 選択テキスト用の selection action HUD を開く（Translate / Summarize / Task Assistant / Ask AI） |
| `⌘⇧J` | 選択テキストを直接翻訳 |
| `⌘⇧K` | 選択テキストを直接要約 |
| `⌘⇧L` | 選択テキストを Task Assistant に送る |
| `⌘⇧P` | 選択テキストを Ask AI chat HUD に送る |

Selection-action shortcuts は **Settings -> Selection Actions -> Activation** で個別に変更またはクリアできます。

## 使い方

### 音声入力

1. 任意のテキスト欄にカーソルを置く。
2. 音声入力ショートカットを押し続ける。
3. 話す。オーバーレイにライブ認識が表示される。
4. ショートカットを離す。final text がカーソル位置に挿入される。

### 音声メモ

Workbench を開いて **Notes** に移動します。録音ボタンをクリックすると簡単なメモを開始できます。VoxFlow は話している間に文字起こしし、完了後に編集や確認ができます。

### ファイル文字起こし

**File Transcription** を開き、音声または動画ファイルを選択します。完了した job はコピー、export、notes への保存ができます。

### クリップボード画像 OCR

スクリーンショットまたは画像をコピーし、`⌘⇧V` を押します。VoxFlow はクリップボードの画像を読み取り、OCR を実行し、認識テキストを現在のカーソル位置に貼り付けます。

クリップボードに画像がない場合、このショートカットは通常の音声入力を開始しません。クリップボード画像 OCR 専用です。

### スクリーンショット OCR、翻訳、要約

`⌘⇧A` を押して画面領域を選択します。VoxFlow はその領域をキャプチャし、OCR を実行し、**Original Image**、**OCR**、**Translation**、**Summary** タブを持つ結果パネルを開きます。パネルから利用可能なテキストをコピーまたは読み上げできます。

翻訳には Apple システム翻訳、設定済み LLM、またはローカル翻訳モデルを使えます。要約には設定済み LLM またはローカル要約器を使えます。翻訳や要約モデルがなくても、OCR テキストはそのまま利用できます。

### スクリーンショット／収録記録ライブラリ

`⌘⇧A` で取得したスクリーンショットはすべてローカル記録として保存され、後で **Workbench -> Screenshot** から確認できます。
検索、お気に入りフィルタ、ページサイズ切り替え、認識テキストのコピー、削除に対応します。
画像プレビューはローカルファイルから読み込まれ、同期やアップロードはされません。

### Agent Compose

Agent Compose は、現在ウィンドウの可視テキストと任意の OCR 文脈を読み取り、話した意図と組み合わせ、ChatGPT、Claude、Codex、Cursor などの AI ツール向けプロンプトを作ります。安全境界は維持されます。コピーのみで、挿入や自動送信はしません。

### AI Coding 助手 Command Center

Settings で AI Coding 助手 Command Center を有効にし、既存の音声ショートカットで command HUD に入ります。たとえば “frontend, check the button state” のように Agent 名とタスクを話すと、VoxFlow が対象を解決し、必要に応じて確認し、その terminal agent session に指示を送ります。

### Launcher: Ask AI、Quicklinks、Open URL

`⌥Space` でランチャーを開きます。アプリ、コマンド、資産検索に加えて、次のことができます。

- **Ask AI**: 質問を入力し、"Ask AI" を選んで Enter。ランチャーが閉じ、右側 HUD が Ask AI chat mode に入ります。設定済み LLM provider を再利用し、複数ターン会話、ストリーミング返信、Markdown rendering に対応します。セッションはメモリに残るので、Ask AI を開き直して follow-up を続けられます。provider が未設定の場合、送信せず設定ヒントを表示します。
- **Quicklinks**: 内蔵サイトは Google、Bing、Perplexity、GitHub、StackOverflow、YouTube、Bilibili、X、Xiaohongshu、Taobao、JD です。サイト名、中国語名、alias（`gh`、`tb`、`b站` など）を入力するとそのサイトが優先され、Enter で既定ブラウザに検索結果を開きます。
- **Open URL**: 完全な URL、`github.com/openai/codex` のような裸ドメイン、`localhost:3000`、`127.0.0.1:8080` を入力すると、最初の結果が自動的に "Open URL" になり、Enter で既定ブラウザに開きます。裸ドメインは `https://` に正規化されます。

Selection action panel（`⌘⇧F`）と direct selection Ask AI shortcut（`⌘⇧P`）は、どちらも選択テキストを同じ Ask AI chat HUD に送るので、先にランチャーを開く必要はありません。

### 名前と用語を改善する

**Personal Corrections** を使って決定的な修正を設定できます。あるいは current-window OCR context boost を有効にし、プロジェクト名、人名、製品名、技術用語を現在タスク向けの一時 hotword にできます。

### LLM 修正を有効にする

**Settings -> Models** を開き、OpenAI 互換 provider を追加し、Base URL、Model、API Key を入力して接続テストを行います。成功したら同じ settings page で **LLM Correction** を有効にします。

LLM API key は macOS Keychain に保存されます。Groq、Tencent Cloud、Alibaba Cloud の cloud ASR credentials はローカル SQLite settings database に保存され、Models から表示、非表示、削除できます。

## プライバシー

VoxFlow は標準で local-first です。

- 資産履歴、Personal Correction rules、notes、transcription jobs、非秘密設定はローカルに保存されます。
- LLM API key は macOS Keychain に保存されます。cloud ASR credentials はローカル SQLite settings database に保存されます。
- Apple Speech は macOS のシステム挙動に従って音声を処理する場合があります。
- Local Qwen3-ASR はモデルダウンロード後、端末上で実行されます。
- LLM correction は標準で無効です。有効化すると、認識テキストだけが設定済み API provider に送信されます。
- cloud ASR provider を選ぶと、録音音声はその provider に送信されます。ローカルモデルでは音声は端末内に留まります。VoxFlow は notes、asset history、clipboard content を能動的にアップロードしません。
- Clipboard assets は launcher と Home review のためローカル保存されます。ノイズフィルタは意味の薄い高頻度変更を除外します。
- Clipboard image OCR は一回限りの OCR entry としても使えます。
- Screenshot / recording records（`⌘⇧A` で取得した OCR text + screenshot files）はローカル保存され、アップロードされません。

詳しくは [Privacy](docs/PRIVACY.md) を参照してください。

## FAQ

| Question | Answer |
| --- | --- |
| ショートカットが何もしない | Accessibility 権限を確認し、VoxFlow を終了して開き直してください |
| オーバーレイは出るが文字が表示されない | Microphone、Speech Recognition、選択中モデルの状態を確認してください |
| スクリーンショット／収録記録が見つからない | Settings -> Data & Privacy -> Data Management で storage health を確認し、data folder を開いて `Application Support/VoxFlow/Screenshots/` に画像記録があるか確認してください。Screen Recording 権限も確認してください |
| 既定の screenshot annotation tool を無効にするには | 現バージョンでは永続的な "default annotation tool" 設定はありません。各 capture panel で Select/Cursor tool に切り替えると、annotation mode を避けられます |
| LLM correction が動かない | Settings で有効化されていること、default provider が connection test に通ることを確認してください |
| API key が隠れている理由 | 仕様です。確認する必要がある場合は編集時に reveal button を使ってください |
| オフラインで使えるか | ローカル Qwen3-ASR モデルをダウンロードして選択してください |
| 削除した履歴や notes は復元できるか | 削除はローカルで即時実行されます。削除前に確認してください |

## ソースから実行

自分でビルドする場合:

```bash
git clone https://github.com/xingbofeng/VoxFlow.git
cd VoxFlow
make run-dev
```

よく使うコマンド:

```bash
make run-dev      # 日常開発: Debug + native arch、.app を package して起動
make run-native   # 出荷挙動に近い Native Release のローカル確認
make build        # arm64 Release。release/DMG 用
make install      # /Applications にインストール
swift test        # テスト実行
```

## 技術スタックとオープンソース依存

VoxFlow は Electron wrapper ではなく、ネイティブ macOS アプリです。コードベースは SwiftPM target に分かれ、local-first path を標準でローカルに保ち、ユーザーが明示的に設定した cloud provider だけを使います。

| Area | Stack / Open-Source Dependency | 用途 |
| --- | --- | --- |
| App shell | Swift 6、SwiftUI、AppKit、SwiftPM | Menu-bar app、Workbench、Settings、HUD、macOS window lifecycle |
| System APIs | AVFoundation、Speech、Vision、Accessibility、Pasteboard | 録音、Apple Speech、screenshot/clipboard OCR、text insertion、current-window context |
| Screenshot capture & annotation | VoxFlowScreenshotKit、ScreenCaptureKit、CoreGraphics、Vision | Region capture、annotation tools、scroll capture、screenshot rendering |
| Local ASR | speech-swift Qwen3ASR / Nemotron、WhisperKit、FluidAudio、Sherpa-ONNX vendor runtime | Qwen3-ASR、NVIDIA Nemotron、Whisper、SenseVoice、Paraformer、FunASR routes |
| Cloud ASR / LLM | OpenAI-compatible HTTP、Groq、Tencent Cloud realtime ASR、Alibaba DashScope | Online transcription、LLM correction、translation fallback、summary、Agent Compose |
| Personal Corrections | `Packages/VoxFlowVoiceCorrectionKit`、TypeWhisper deterministic post-processing と focused text observation に着想 | Local rule matching、conflict resolution、learned candidates、benchmark fixtures |
| Context hotwords | `Packages/VoxFlowContextBoostKit`、Vision OCR、NaturalLanguage | 現在ウィンドウ OCR text から現在 prompt 専用の一時 Top-K hotword を抽出 |
| AI Coding 助手 | Rust `agent-cli/` helper/router、JSON IPC、MCP self-reporting | ローカル Codex、Claude、CodeBuddy、terminal agent へ音声指示を dispatch |
| Verification | XCTest、Makefile、GitHub Actions、JiWER cross-check scripts | Unit tests、release builds、ASR/correction benchmarks、metric validation |

Attribution と license notes は関連モジュールの近くにあります。`Packages/VoxFlowVoiceCorrectionKit/NOTICE.md`、`SOURCE_ATTRIBUTION.md`、`MODIFICATIONS.md` は TypeWhisper 参照と adaptation boundary を記録します。`Vendor/` には packaged local runtime/vendor assets が含まれます。AI Coding 助手 は Rust helper だけを維持し、古い Python CLI は配布しません。

### Source Layout

```
Sources/                         # Swift app code, domain modules, ASR providers, text insertion, and other SwiftPM targets
Packages/VoxFlowVoiceCorrectionKit/ # Personal Corrections engine, benchmark fixtures, and package tests
agent-cli/                       # Rust helper/router source for AI Coding 助手; builds the bundled `voxflow` binary and `vox` shim
Tests/                           # Swift unit tests plus Python tests for ASR benchmark tooling
Resources/                       # App icon and bundled resources
Vendor/                          # Local runtime/vendor assets required by packaged builds
docs/                            # GitHub Pages site, privacy docs, design notes, and implementation plans
scripts/                         # Build, ASR benchmark, and architecture-check helper scripts
tools/                           # Auxiliary verification tools; currently JiWER cross-check only, not an agent CLI
.github/                         # CI, Pages, Release workflows, and release notes
```

AI Coding 助手 の CLI 実装は 1 つだけです。root-level `agent-cli/` の Rust source が保守対象です。古い Python `vf-agent` / `agent-cli` reference helper は削除済みです。残っている Python files は benchmark、architecture check、Personal Corrections metric cross-check 用であり、app runtime の一部ではなく、ユーザー向け CLI として配布されません。

## サードパーティモジュールとオープンソースライセンス

### License

VoxFlow は GPL-3.0-or-later で配布されます。サードパーティ components はそれぞれの license notice と attribution を保持します。`docs/third-party-licenses.md` を参照してください。

### Third-Party Modules

### Unified Modules and References

| Type | Module / Source | Link | 用途 |
| --- | --- | --- | --- |
| Third-party dependency | `speech-swift` (`Qwen3ASR`, `NemotronStreamingASR`, `ParakeetStreamingASR`, `OmnilingualASR`, `Qwen3TTS`, `Qwen3Chat`, `KokoroTTS`, `MADLADTranslation`) | [GitHub](https://github.com/soniqo/speech-swift.git) | Local ASR/TTS/translation/chat runtime |
| Third-party dependency | `WhisperKit` | [GitHub](https://github.com/argmaxinc/WhisperKit.git) | Local Whisper transcription |
| Third-party dependency | `FluidAudio` | [GitHub](https://github.com/FluidInference/FluidAudio.git) | Paraformer/SenseVoice 用 local ASR pipeline |
| Third-party dependency | `Sherpa-ONNX` | [GitHub](https://github.com/k2-fsa/sherpa-onnx.git) | FunASR local inference runtime |
| Third-party dependency | `onnxruntime` (`Vendor/CSherpaOnnx`) | [GitHub](https://github.com/microsoft/onnxruntime) | Sherpa-ONNX と一緒に bundled される inference runtime |
| In-repo module | `VoxFlowContextBoostKit` | [Repo path](Packages/VoxFlowContextBoostKit) | OCR context hotword extraction |
| In-repo module | `VoxFlowVoiceCorrectionKit` | [Repo path](Packages/VoxFlowVoiceCorrectionKit) | Deterministic correction engine and benchmarks |
| In-repo module | `agent-cli` (Rust) | [Repo path](agent-cli) | Local terminal AI agent dispatching helper |
| Reference source | TypeWhisper | [GitHub](https://github.com/TypeWhisper/typewhisper-mac) | Deterministic correction flow + focused observation learning（概念参照のみ。source copy なし） |
| Reference source | FlashText | [GitHub](https://github.com/vi3k6i5/flashtext) | Matching/replacement approach inspiration（runtime reuse なし） |
| Reference source | JiWER | [GitHub](https://github.com/jitsi/jiwer) | Evaluation and benchmark cross-check reference |
| Reference source | OpenAI Evals | [GitHub](https://github.com/openai/evals) | Benchmark/test-case organization style reference |
| Reference source | LanguageTool | [GitHub](https://github.com/languagetool-org/languagetool) | Error-correction fixture and testing style reference |

### License and Attribution References

| Path | 内容 |
| --- | --- |
| `LICENSE` | Project-level license |
| `SOURCE_ATTRIBUTION.md` | Third-party source references and adaptation scope |
| `MODIFICATIONS.md` | Upstream adaptation notes |
| `Packages/VoxFlowVoiceCorrectionKit/NOTICE.md` | TypeWhisper-derived source licensing |
| `Vendor/` | Vendored runtime license declarations |
| `Package.swift` + `NOTICE/LICENSE` in `Sources/` and `Packages/` | Component dependency and license declarations |

## X でつながる

X でフォローしてください: [@Counterxing](https://x.com/Counterxing)
