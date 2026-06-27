<div align="center">
  <img src="docs/assets/voiceinput-logo.png" alt="VoxFlow logo" width="128">

  <h1>VoxFlow</h1>
  <p><strong>음성, 스크린샷, 화면 녹화, 클립보드 기록, coding-agent 지시를 위한 macOS 자산 워크벤치.</strong></p>
  <p><code>⌥Space</code>로 런처를 열고 최근 음성, 스크린샷, 화면 녹화, 클립보드 자산을 다시 찾을 수 있습니다. 받아쓰기, 캡처, 녹화, 복사한 내용은 검색 가능하고 복사 가능하며 재사용 가능한 로컬 기록이 됩니다.</p>

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

## 한눈에 보기

VoxFlow는 지금 사용 중인 앱에 붙는 자산 워크벤치이자 빠른 런처입니다. 음성 비서가 아닙니다. 창을 빼앗지 않고, 메시지를 자동 전송하지 않으며, 다른 입력창으로 이동시키지 않습니다. 음성, 스크린샷, 화면 녹화, 클립보드 항목, Agent 명령을 검색, 미리보기, 재사용 가능한 로컬 자산으로 만들고 다시 현재 작업 공간으로 돌려보냅니다.

| 하고 싶은 일 | 트리거 | 출력 위치 | 경계 |
| --- | --- | --- | --- |
| 런처 열기 | `⌥Space` | Raycast 스타일 런처 | Recent Assets가 기본 선택되며 키보드 탐색 우선 |
| 최근 자산 찾기 | Launcher -> Recent Assets | 2단계 자산 브라우저 | 음성, 스크린샷, 클립보드가 공통 검색과 필터를 공유 |
| 텍스트 받아쓰기 | 단축키를 누르고 말한 뒤 떼기 | 현재 커서 위치 | 포커스 탈취 없음, 자동 전송 없음 |
| 클립보드 자산 관리 | 텍스트, 이미지, 파일, 링크, 색상 복사 | 자산 기록 | 노이즈 필터가 저장하지 않아야 할 내용을 건너뜀 |
| 잘못 인식된 용어 수정 | ASR final output과 선택적 LLM correction 뒤 실행 | 삽입 전 텍스트 | 로컬 결정적 규칙. 학습 후보는 사용자가 제어 |
| 클립보드 이미지 OCR | 이미지를 복사하고 `⌘⇧V` | 현재 커서 위치 | 이미지 전용 워크플로. 일반 받아쓰기를 시작하지 않음 |
| 스크린샷이나 화면 녹화를 처리 | `⌘⇧A`를 누르고 영역 선택 | OCR 결과 패널 | 번역, 요약, 읽어주기는 선택 사항 |
| 선택 텍스트 작업 | 텍스트를 선택하고 `⌘⇧F/J/K/L/P` | Action HUD 또는 결과 패널 | F는 action card, J는 번역, K는 요약, L은 Task Assistant, P는 Ask AI |
| 런처에서 Ask AI | 런처에 질문 입력 후 Ask AI 선택 | Ask AI chat HUD | 설정된 LLM provider 재사용. 멀티턴, 스트리밍, Markdown 지원 |
| 런처에서 웹 검색 | 키워드 입력 후 Quicklink 선택 | 기본 브라우저 | Google, Bing, Perplexity, GitHub, StackOverflow, YouTube, Bilibili, X, Xiaohongshu, Taobao, JD 내장 |
| URL 열기 | URL 또는 bare domain 입력 | 기본 브라우저 | http/https/bare domain/localhost/IP+port 자동 감지. 첫 결과가 Open URL |
| 스크린샷/화면 녹화 기록 보기 | Workbench -> Screenshot | 로컬 스크린샷과 화면 녹화 기록, OCR 텍스트 | 로컬 저장. 검색, 즐겨찾기, 복사, 삭제 가능 |
| AI 프롬프트 만들기 | 현재 창 맥락 + 말한 의도 | 복사 가능한 프롬프트 | 복사만 수행. 삽입, 자동 전송 없음 |
| 로컬 coding agent 명령 | task assistant 이름과 작업을 말하기 | Codex / Claude / CodeBuddy / terminal agent session | 등록된 세션에만 dispatch |

## 이런 사람에게 맞습니다

- ChatGPT, Claude, Codex, Cursor 같은 AI 도구에 의도, 맥락, 수정 요청을 빠르게 전달해야 하는 사람.
- Codex, Claude, CodeBuddy 또는 다른 터미널 Agent를 실행하고, 음성 지시를 올바른 로컬 세션으로 보내고 싶은 사람.
- 코드를 쓰면서 버그 설명, 메모, 커밋 메시지, 조사 기록을 자주 작성하는 사람.
- 스크린샷, 웹 페이지, 오류 대화상자, 이미지에서 텍스트를 추출한 뒤 번역하거나 요약하는 사람.
- 중국어와 영어를 섞어 말하며 기술 용어와 제품명이 자주 잘못 인식되는 사람.

## 읽는 순서

| 알고 싶은 것 | 시작 위치 |
| --- | --- |
| 설치해서 바로 써보기 | [빠른 시작](#빠른-시작) |
| 런처와 자산 이해하기 | [수정, OCR, Agent 워크플로](#수정-ocr-agent-워크플로) |
| 음성 모델 이해하기 | [받아쓰기와 음성 모델](#받아쓰기와-음성-모델) |
| OCR, 번역, 요약, Agent 이해하기 | [수정, OCR, Agent 워크플로](#수정-ocr-agent-워크플로) |
| 데이터가 어디로 가는지 확인하기 | [개인정보 보호](#개인정보-보호) |
| 기술 스택과 오픈소스 의존성 이해하기 | [기술 스택과 오픈소스 의존성](#기술-스택과-오픈소스-의존성) |
| 소스에서 빌드하기 | [소스에서 실행](#소스에서-실행) |

## 받아쓰기와 음성 모델

### 누르고 말하고, 떼면 삽입

VoxFlow는 키보드 레이어처럼 동작합니다. 받아쓰기 단축키를 누른 채 말하고 손을 뗍니다. 말하는 동안 작은 전사 오버레이가 나타나고, 최종 텍스트가 현재 커서 위치에 삽입됩니다.

앱을 전환하거나 텍스트를 다시 복사할 필요가 없습니다.

### 실시간 전사

말하는 동안 VoxFlow는 인식된 텍스트를 실시간으로 보여주므로 흐름을 확인할 수 있습니다. 짧은 명령, 긴 설명, 중국어, 영어, 중국어와 영어가 섞인 말에 대응합니다.

VoxFlow에는 시스템 음성 인식기와 로컬/클라우드 ASR provider가 포함됩니다. Apple Speech는 바로 사용할 수 있습니다. Qwen3-ASR, Whisper, FunASR, SenseVoice, NVIDIA Nemotron, Parakeet, Omnilingual은 로컬 워크플로를 담당하고, Groq, Tencent Cloud, Alibaba Cloud는 온라인 인식을 제공합니다. Models 페이지는 로컬/온라인, 스트리밍 가능 여부, 언어 범위를 명확히 표시합니다.

### 지원 음성 모델

VoxFlow는 모든 로컬 모델을 하나의 runtime에 억지로 넣지 않습니다. 각 provider는 upstream model format과 latency 목표에 맞는 경로를 사용합니다.

| Provider / Model | 현재 runtime 경로 | 추천 용도 |
| --- | --- | --- |
| Apple Speech | Apple Speech / SFSpeechRecognizer | 모델 다운로드 없이 바로 쓰는 기본 받아쓰기 |
| Qwen3-ASR 0.6B | speech-swift Qwen3ASR MLX 4bit | 통합 speech-swift runtime을 쓰는 기본 로컬 경로 |
| Qwen3-ASR 1.7B | speech-swift Qwen3ASR MLX 8bit | 0.6B와 같은 로딩/세션 경로를 공유하는 고정확도 로컬 경로 |
| Whisper Turbo / Large V3 | WhisperKit `.mlmodelc` | 녹음 종료 후 고품질 전체 전사 |
| FunASR | Sherpa-ONNX | 중국어 로컬 fallback. CoreML 아님 |
| SenseVoice | FluidAudio / CoreML | 로컬 다국어 및 짧은 발화 전사 |
| Paraformer | FluidAudio / CoreML int8 | 로컬 중국어 전사 |
| NVIDIA Nemotron 0.6B | speech-swift NemotronStreamingASR / CoreML | 로컬 다국어 스트리밍 전사 |
| Parakeet Streaming | speech-swift ParakeetStreamingASR / CoreML | 영어와 유럽 언어용 저지연 로컬 스트리밍 받아쓰기 |
| Omnilingual ASR | speech-swift OmnilingualASR / CoreML | 폭넓은 언어 범위의 오프라인 전사와 실험 워크플로 |

클라우드 provider는 녹음된 오디오를 선택한 서비스로 보냅니다. Groq는 녹음 후 final transcript를 반환하고, Tencent Cloud와 Alibaba Cloud는 실시간 WebSocket 전사를 지원합니다.

| Cloud Provider | 상태 | Streaming | 기본 모델 / API | 설정 |
| --- | --- | --- | --- | --- |
| Groq (Free) | 지원 | No | `whisper-large-v3-turbo` audio transcription | API Key, model |
| Tencent Cloud | 지원 | Yes | Realtime Speech Recognition WebSocket, `16k_zh` | AppID, SecretId, SecretKey |
| Alibaba Cloud | 지원 | Yes | DashScope WebSocket, `fun-asr-realtime` | Bailian API Key |
| Volcengine Cloud | Planned | Planned | Doubao streaming ASR | 미정 |
| Mistral Voxtral, AssemblyAI, ElevenLabs Scribe | 아직 미지원 | 미정 | 예약 provider | 없음 |

## 수정, OCR, Agent 워크플로

### Personal Corrections와 선택적 LLM Correction

음성 인식은 Python, JSON, TypeScript, framework 이름, 제품명 같은 기술 용어에서 흔히 실수합니다. VoxFlow는 받아쓰기가 끝난 뒤 사용자가 설정한 OpenAI-compatible provider를 통해 보수적인 correction pass를 실행할 수 있습니다.

새 **Personal Corrections** 페이지는 ASR final output과 선택적 LLM correction 뒤에 결정적 로컬 수정을 실행합니다. 삽입 후 사용자가 직접 수정한 내용에서 후보 규칙을 학습할 수도 있습니다. LLM pass는 의도적으로 제한적입니다. 문체를 다듬거나 다시 쓰지 않고, 명백한 인식 오류만 고칩니다.

### 클립보드 OCR, 스크린샷 캡처, 번역, 요약

스크린샷을 복사하고 `⌘⇧V`를 누르면 클립보드 이미지를 OCR하고 인식된 텍스트를 현재 커서 위치에 붙여 넣습니다. `⌘⇧A`를 눌러 화면 영역을 선택하면 **Original Image**, **OCR**, **Translation**, **Summary** 탭이 있는 결과 패널이 열립니다.

웹 페이지, 오류 대화상자, 스크린샷, 디자인 mockup, 채팅 기록에 유용합니다. OCR 텍스트는 복사, 읽어주기, 번역, 요약할 수 있지만 영구 Personal Corrections 학습 루프에는 들어가지 않습니다.

### Agent Compose와 AI Coding 助手 Command Center

**Agent Compose**는 현재 창의 보이는 맥락, OCR 텍스트, 말한 의도를 결합해 AI 도구에 붙여 넣을 수 있는 프롬프트를 만듭니다. 결과는 복사만 합니다. 삽입, 제출, Enter 입력은 하지 않습니다.

**AI Coding 助手 Command Center**는 로컬 coding-agent 터미널을 위한 기능입니다. 활성화한 뒤 task assistant 이름과 지시를 말하면, VoxFlow가 대상 Agent를 찾고 확인 상태를 보여준 다음 해당 Codex, Claude, CodeBuddy 또는 등록된 terminal session에 지시를 보냅니다.

### Workbench

VoxFlow에는 전체 자산 워크벤치도 포함됩니다.

| Page | 할 수 있는 일 |
| --- | --- |
| Home | 자산 기록, 오늘 추가된 항목, source breakdown, 재사용 가능한 내용을 확인하고 음성, 스크린샷, 화면 녹화, 클립보드 자산을 검색, 복사, 삭제 |
| Personal Corrections | 결정적 correction rules, learned candidates, enablement, recent events 관리 |
| Styles | original, formal, email, coding notes 같은 출력 스타일 선택 |
| File Transcription | 오디오 또는 비디오 파일을 가져와 전사하고 txt/md/srt로 export하거나 notes로 저장 |
| Notes | 음성 메모 녹음, Markdown 편집, 검색, 최근 notes 확인 |
| Screenshot | OCR 텍스트가 포함된 캡처 스크린샷과 화면 녹화를 favorites, search, paging과 함께 탐색 |
| AI Coding 助手 | 등록된 agents, aliases, working directories, branches, dispatch logs 확인 |
| Settings | 입력 장치, 단축키, 모델, 번역 모델, 권한, 개인정보, 데이터 관리 |
| Help | 권한 안내, 버전 정보, 프로젝트 링크 확인 |

## 주요 기능

- **VoxFlow Palette launcher**: `⌥Space`로 Raycast 스타일 런처를 열며 Recent Assets가 기본 선택됩니다. 방향키, Enter, `⌘K` actions를 지원합니다.
- **Asset history workbench**: 성공한 ASR 텍스트, 스크린샷, 화면 녹화, 클립보드 텍스트/이미지/파일/링크/색상이 하나의 자산 시스템을 공유합니다. Home은 자산 수, source breakdown, 재사용 가능한 내용을 보여줍니다.
- **Global dictation**: VoxFlow 내부뿐 아니라 모든 편집 가능한 텍스트 필드에서 동작합니다.
- **Non-intrusive overlay**: 포커스를 빼앗지 않고 live text와 voice activity를 표시합니다.
- **Multiple ASR providers**: 내장 시스템 인식기로 시작할 수 있습니다. 로컬 Qwen3-ASR, Whisper, FunASR, SenseVoice, NVIDIA Nemotron, Parakeet, Omnilingual provider가 같은 runtime model 아래 통합되고 있습니다. 실시간 스트리밍이 없는 provider는 Models에서 **Non-streaming**으로 표시됩니다.
- **Stable text insertion**: 붙여넣기 전에 입력 소스를 잠시 전환하고, 완료 후 입력 소스와 클립보드를 복원해 CJK 입력기 간섭을 줄입니다.
- **Input device selection**: 마이크를 선택할 수 있으며 긴 장치명도 UI를 무너뜨리지 않습니다.
- **Shortcut recording**: 원하는 키를 녹화하고 short-press 동작을 설정할 수 있습니다.
- **Clipboard image OCR**: 스크린샷이나 이미지를 복사하고 `⌘⇧V`를 누르면 이미지 텍스트를 인식해 현재 필드에 붙여 넣습니다.
- **Screenshot OCR**: `⌘⇧A`를 누르고 화면 영역을 선택한 뒤 original image, OCR text, translation, summary를 결과 패널에서 확인합니다.
- **Screenshot / recording library**: 캡처한 스크린샷과 화면 녹화는 Screenshot 페이지에 OCR text, favorites, search, one-click copy/delete actions와 함께 보관됩니다.
- **Inline screenshot annotation**: 영역 캡처는 pen/shape/text/mosaic/scroll tools, undo/redo, 최종 insert/output 전 quick translate/summary flow를 지원합니다.
- **AI Coding 助手 Command Center**: 음성 지시를 Codex, Claude, CodeBuddy 또는 등록된 로컬 terminal agents로 보냅니다.
- **Agent Compose**: 현재 창 OCR 맥락과 말한 의도를 프롬프트로 만듭니다. 결과는 복사만 하고 자동 제출하지 않습니다.
- **OpenAI-compatible providers**: provider를 추가, 테스트, 편집, 삭제할 수 있습니다. LLM API keys는 macOS Keychain에 저장됩니다.
- **Personal corrections and context hotwords**: 반복되는 오인식을 로컬 규칙으로 고치고, 현재 창 OCR에서 임시 context terms를 추출합니다.
- **History and notes**: 이전 입력, 스크린샷, 복사한 내용을 검색, 복사, 편집, 재사용합니다.
- **File transcription**: 녹음, 영상, 회의 오디오를 텍스트로 변환합니다.
- **Local-first data**: 기록, personal corrections, settings, notes, jobs는 로컬에 저장됩니다. LLM correction은 opt-in입니다.

## 빠른 시작

### 다운로드와 설치

[GitHub Releases](https://github.com/xingbofeng/VoxFlow/releases/latest)에서 최신 버전을 다운로드합니다.

1. `VoxFlow-1.9.0-macOS.dmg` 열기
2. `VoxFlow`를 `Applications` 폴더로 드래그
3. 첫 실행 시 macOS가 앱을 확인할 수 없다고 하면, Control-click 후 **Open** 선택

설치 후 Workbench -> Screenshot을 열어 스크린샷과 화면 녹화 기록, OCR 기록이 사용 가능한지 확인할 수 있습니다.

> Personal Corrections, AI Coding 助手, Screenshot OCR의 main branch 최신 구현을 써보고 싶다면 소스에서 실행하세요. 이 기능들은 최신 stable Release보다 새로울 수 있습니다.

### 요구 사항

- macOS 15 Sequoia 이상
- 마이크가 있는 Mac

### 첫 권한 설정

VoxFlow는 몇 가지 macOS 권한이 필요합니다.

| 권한 | 필요한 이유 | 위치 |
| --- | --- | --- |
| Accessibility | 전역 단축키를 듣고 현재 앱에 텍스트 삽입 | System Settings -> Privacy & Security -> Accessibility |
| Microphone | 음성 녹음 | System Settings -> Privacy & Security -> Microphone |
| Speech Recognition | 시스템 음성 인식기 사용 | System Settings -> Privacy & Security -> Speech Recognition |
| Screen Recording | Agent Compose, screenshot OCR, 화면 녹화를 위해 현재 창 OCR | System Settings -> Privacy & Security -> Screen Recording |

로컬 Qwen3-ASR 모델을 사용하면 Speech Recognition 권한은 필요하지 않습니다. Microphone 권한은 여전히 필요합니다.

권한을 허용한 뒤에도 단축키가 반응하지 않으면 VoxFlow를 종료하고 다시 여세요.

### 기본 단축키

| Shortcut | Action |
| --- | --- |
| `⌥Space` | VoxFlow Palette launcher 열기 |
| Dictation shortcut | 누르고 말하고, 떼면 현재 커서에 삽입. Settings에서 변경 가능 |
| `⌘⇧V` | 클립보드 이미지를 OCR하고 인식 텍스트 붙여넣기 |
| `⌘⇧A` | 화면 영역 캡처 후 OCR 결과 패널 열기 |
| `⌘⇧F` | 선택 텍스트용 selection action HUD 열기(Translate / Summarize / Task Assistant / Ask AI) |
| `⌘⇧J` | 선택 텍스트 직접 번역 |
| `⌘⇧K` | 선택 텍스트 직접 요약 |
| `⌘⇧L` | 선택 텍스트를 Task Assistant로 보내기 |
| `⌘⇧P` | 선택 텍스트를 Ask AI chat HUD로 보내기 |

Selection-action shortcuts는 **Settings -> Selection Actions -> Activation**에서 개별 변경 또는 제거할 수 있습니다.

## 사용 방법

### 받아쓰기

1. 아무 텍스트 필드에 커서를 둡니다.
2. 받아쓰기 단축키를 누릅니다.
3. 말합니다. 오버레이가 live recognition을 보여줍니다.
4. 단축키에서 손을 뗍니다. final text가 커서 위치에 삽입됩니다.

### 음성 메모

Workbench를 열고 **Notes**로 이동합니다. 녹음 버튼을 클릭하면 빠른 메모를 시작할 수 있습니다. VoxFlow는 말하는 동안 전사하고, 이후 편집과 확인을 할 수 있게 합니다.

### 파일 전사

**File Transcription**을 열고 오디오 또는 비디오 파일을 선택합니다. 완료된 job은 복사, export, notes 저장이 가능합니다.

### 클립보드 이미지 OCR

스크린샷이나 이미지를 복사한 뒤 `⌘⇧V`를 누릅니다. VoxFlow는 클립보드 이미지를 읽고 OCR을 실행한 다음 인식된 텍스트를 현재 커서 위치에 붙여 넣습니다.

클립보드에 이미지가 없으면 이 단축키는 일반 받아쓰기를 시작하지 않습니다. 클립보드 이미지 OCR 전용입니다.

### 스크린샷 OCR, 번역, 요약

`⌘⇧A`를 누른 뒤 화면 영역을 선택합니다. VoxFlow는 해당 영역을 캡처하고 OCR을 실행하며 **Original Image**, **OCR**, **Translation**, **Summary** 탭이 있는 결과 패널을 엽니다. 패널에서 가능한 텍스트를 복사하거나 읽어줄 수 있습니다.

번역은 Apple system translation, 설정된 LLM, 또는 로컬 translation model을 사용할 수 있습니다. 요약은 설정된 LLM 또는 로컬 summarizer를 사용할 수 있습니다. 번역이나 요약 모델이 없어도 OCR 텍스트는 그대로 사용할 수 있습니다.

### 스크린샷 기록 라이브러리

`⌘⇧A`로 캡처한 모든 스크린샷은 로컬 screenshot record로 저장되며 나중에 **Workbench -> Screenshot**에서 확인할 수 있습니다.
검색, favorites 필터, page size 변경, 인식 텍스트 복사, 삭제를 지원합니다.
이미지 미리보기는 로컬 파일에서 로드되며 동기화되거나 업로드되지 않습니다.

### Agent Compose

Agent Compose는 현재 창의 보이는 텍스트와 선택적 OCR 맥락을 읽고, 말한 의도와 결합해 ChatGPT, Claude, Codex, Cursor 같은 AI 도구용 프롬프트를 만듭니다. 안전 경계를 유지합니다. 복사만 하고 삽입이나 자동 제출은 하지 않습니다.

### AI Coding 助手 Command Center

Settings에서 AI Coding 助手 Command Center를 켠 다음 기존 음성 단축키로 command HUD에 들어갑니다. “frontend, check the button state”처럼 agent 이름과 작업을 말하면 VoxFlow가 대상을 찾고, 필요하면 확인을 요청하고, 해당 terminal agent session으로 지시를 보냅니다.

### Launcher: Ask AI, Quicklinks, Open URL

`⌥Space`로 런처를 엽니다. 앱, 명령, 자산 검색 외에도 다음을 할 수 있습니다.

- **Ask AI**: 질문을 입력하고 "Ask AI"를 선택한 뒤 Enter. 런처가 닫히고 오른쪽 HUD가 Ask AI chat mode로 들어갑니다. 설정된 LLM provider를 재사용하며 멀티턴 대화, streaming replies, Markdown rendering을 지원합니다. 세션은 메모리에 유지되므로 Ask AI를 다시 열어 follow-up을 이어갈 수 있습니다. provider가 설정되지 않았다면 요청을 보내지 않고 설정 안내를 표시합니다.
- **Quicklinks**: 내장 사이트는 Google, Bing, Perplexity, GitHub, StackOverflow, YouTube, Bilibili, X, Xiaohongshu, Taobao, JD입니다. 사이트명, 중국어명, alias(`gh`, `tb`, `b站` 등)를 입력하면 해당 사이트가 우선되며, Enter를 누르면 기본 브라우저에서 검색 결과가 열립니다.
- **Open URL**: 전체 URL, `github.com/openai/codex` 같은 bare domain, `localhost:3000`, `127.0.0.1:8080`을 입력하면 첫 결과가 자동으로 "Open URL"로 선택되고 Enter로 기본 브라우저에서 열립니다. bare domain은 `https://`로 정규화됩니다.

Selection action panel(`⌘⇧F`)과 direct selection Ask AI shortcut(`⌘⇧P`)은 모두 선택 텍스트를 같은 Ask AI chat HUD로 보내므로 런처를 먼저 열 필요가 없습니다.

### 이름과 용어 개선

**Personal Corrections**로 결정적 수정을 설정하거나, current-window OCR context boost를 켜서 프로젝트명, 사람 이름, 제품명, 기술 용어를 현재 작업용 임시 hotword로 만들 수 있습니다.

### LLM Correction 활성화

**Settings -> Models**를 열고 OpenAI-compatible provider를 추가한 뒤 Base URL, Model, API Key를 입력하고 연결을 테스트합니다. 작동하면 같은 settings page에서 **LLM Correction**을 켭니다.

LLM API keys는 macOS Keychain에 저장됩니다. Groq, Tencent Cloud, Alibaba Cloud의 cloud ASR credentials는 로컬 SQLite settings database에 저장되며 Models에서 표시, 숨김, 제거할 수 있습니다.

## 개인정보 보호

VoxFlow는 기본적으로 local-first입니다.

- 자산 기록, personal correction rules, notes, transcription jobs, secret이 아닌 settings는 로컬에 저장됩니다.
- LLM API keys는 macOS Keychain에 저장됩니다. cloud ASR credentials는 로컬 SQLite settings database에 저장됩니다.
- Apple Speech는 macOS system behavior에 따라 오디오를 처리할 수 있습니다.
- Local Qwen3-ASR는 모델 다운로드 후 기기에서 실행됩니다.
- LLM correction은 기본적으로 비활성화되어 있습니다. 활성화하면 인식된 텍스트만 설정한 API provider로 전송됩니다.
- cloud ASR provider를 선택하면 녹음된 오디오가 해당 provider로 전송됩니다. 로컬 모델은 오디오를 기기 안에 유지합니다. VoxFlow는 notes, asset history, clipboard content를 능동적으로 업로드하지 않습니다.
- Clipboard assets는 launcher와 Home review를 위해 로컬에 저장됩니다. 노이즈 필터는 의미 없는 고빈도 변경을 건너뜁니다.
- Clipboard image OCR은 일회성 OCR entry로도 사용할 수 있습니다.
- Screenshot / recording records(`⌘⇧A`로 캡처한 OCR text + screenshot files)는 로컬에 저장되며 업로드되지 않습니다.

자세한 내용은 [Privacy](docs/PRIVACY.md)를 참고하세요.

## FAQ

| Question | Answer |
| --- | --- |
| 단축키가 아무것도 하지 않음 | Accessibility 권한을 확인한 뒤 VoxFlow를 종료하고 다시 여세요 |
| 오버레이는 보이지만 텍스트가 나오지 않음 | Microphone, Speech Recognition, 선택한 모델 상태를 확인하세요 |
| 스크린샷/화면 녹화 기록이 없음 | Settings -> Data & Privacy -> Data Management에서 storage health를 확인하고 data folder를 열어 `Application Support/VoxFlow/Screenshots/`에 이미지 기록이 있는지 확인하세요. Screen Recording 권한도 확인하세요 |
| 기본 screenshot annotation tool을 비활성화하려면 | 현재 버전은 영구적인 "default annotation tool" 설정을 제공하지 않습니다. 각 capture panel에서 Select/Cursor tool로 전환하면 기본 annotation mode 진입을 피할 수 있습니다 |
| LLM correction이 실행되지 않음 | Settings에서 활성화되어 있고 default provider가 connection test를 통과하는지 확인하세요 |
| API key가 숨겨져 있는 이유 | 정상 동작입니다. 확인해야 한다면 편집 중 reveal button을 사용하세요 |
| 오프라인으로 쓸 수 있나요 | 로컬 Qwen3-ASR 모델을 다운로드하고 선택하세요 |
| 삭제한 기록이나 notes를 복원할 수 있나요 | 삭제는 로컬에서 즉시 실행되므로 삭제 전 확인하세요 |

## 소스에서 실행

직접 앱을 빌드하려면:

```bash
git clone https://github.com/xingbofeng/VoxFlow.git
cd VoxFlow
make run-dev
```

자주 쓰는 명령:

```bash
make run-dev      # 일상 개발: Debug + native arch, .app package 후 launch
make run-native   # 배포 동작에 가까운 Native Release 로컬 확인
make build        # arm64 Release, release/DMG에 사용
make install      # /Applications에 설치
swift test        # 테스트 실행
```

## 기술 스택과 오픈소스 의존성

VoxFlow는 Electron wrapper가 아닌 네이티브 macOS 앱입니다. 코드베이스는 SwiftPM targets로 나뉘며, local-first 경로는 기본적으로 로컬에 유지하고 사용자가 명시적으로 설정한 cloud provider만 사용합니다.

| Area | Stack / Open-Source Dependency | 용도 |
| --- | --- | --- |
| App shell | Swift 6, SwiftUI, AppKit, SwiftPM | Menu-bar app, Workbench, Settings, HUD, macOS window lifecycle |
| System APIs | AVFoundation, Speech, Vision, Accessibility, Pasteboard | Recording, Apple Speech, screenshot/clipboard OCR, text insertion, current-window context |
| Screenshot capture & annotation | VoxFlowScreenshotKit, ScreenCaptureKit, CoreGraphics, Vision | Region capture, annotation tools, scroll capture, screenshot rendering |
| Local ASR | speech-swift Qwen3ASR / Nemotron, WhisperKit, FluidAudio, Sherpa-ONNX vendor runtime | Qwen3-ASR, NVIDIA Nemotron, Whisper, SenseVoice, Paraformer, FunASR routes |
| Cloud ASR / LLM | OpenAI-compatible HTTP, Groq, Tencent Cloud realtime ASR, Alibaba DashScope | Online transcription, LLM correction, translation fallback, summary, Agent Compose |
| Personal Corrections | `Packages/VoxFlowVoiceCorrectionKit`, TypeWhisper deterministic post-processing와 focused text observation에서 영감 | Local rule matching, conflict resolution, learned candidates, benchmark fixtures |
| Context hotwords | `Packages/VoxFlowContextBoostKit`, Vision OCR, NaturalLanguage | 현재 창 OCR text에서 현재 prompt 전용 임시 Top-K hotwords 추출 |
| AI Coding 助手 | Rust `agent-cli/` helper/router, JSON IPC, MCP self-reporting | 로컬 Codex, Claude, CodeBuddy, terminal agents로 음성 지시 dispatch |
| Verification | XCTest, Makefile, GitHub Actions, JiWER cross-check scripts | Unit tests, release builds, ASR/correction benchmarks, metric validation |

Attribution과 licensing notes는 관련 모듈 옆에 있습니다. `Packages/VoxFlowVoiceCorrectionKit/NOTICE.md`, `SOURCE_ATTRIBUTION.md`, `MODIFICATIONS.md`는 TypeWhisper 참조와 adaptation boundary를 문서화합니다. `Vendor/`에는 packaged local runtime/vendor assets가 있습니다. AI Coding 助手는 Rust helper만 유지하며 오래된 Python CLI는 더 이상 배포하지 않습니다.

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

AI Coding 助手에는 유지되는 CLI 구현이 하나뿐입니다. root-level `agent-cli/`의 Rust source가 그 구현입니다. 예전 Python `vf-agent` / `agent-cli` reference helper는 제거되었습니다. 남은 Python files는 benchmark, architecture check, Personal Corrections metric cross-check용이며 app runtime의 일부가 아니고 사용자-facing CLI로 배포되지 않습니다.

## Third-Party Modules And Open-Source Licenses

### License

VoxFlow는 GPL-3.0-or-later로 배포됩니다. third-party components는 각자의 license notices와 attribution을 유지합니다. `docs/third-party-licenses.md`를 참고하세요.

### Third-Party Modules

### Unified Modules and References

| Type | Module / Source | Link | 용도 |
| --- | --- | --- | --- |
| Third-party dependency | `speech-swift` (`Qwen3ASR`, `NemotronStreamingASR`, `ParakeetStreamingASR`, `OmnilingualASR`, `Qwen3TTS`, `Qwen3Chat`, `KokoroTTS`, `MADLADTranslation`) | [GitHub](https://github.com/soniqo/speech-swift.git) | Local ASR/TTS/translation/chat runtime |
| Third-party dependency | `WhisperKit` | [GitHub](https://github.com/argmaxinc/WhisperKit.git) | Local Whisper transcription |
| Third-party dependency | `FluidAudio` | [GitHub](https://github.com/FluidInference/FluidAudio.git) | Paraformer/SenseVoice용 local ASR pipeline |
| Third-party dependency | `Sherpa-ONNX` | [GitHub](https://github.com/k2-fsa/sherpa-onnx.git) | FunASR local inference runtime |
| Third-party dependency | `onnxruntime` (`Vendor/CSherpaOnnx`) | [GitHub](https://github.com/microsoft/onnxruntime) | Sherpa-ONNX와 함께 번들되는 inference runtime |
| In-repo module | `VoxFlowContextBoostKit` | [Repo path](Packages/VoxFlowContextBoostKit) | OCR context hotword extraction |
| In-repo module | `VoxFlowVoiceCorrectionKit` | [Repo path](Packages/VoxFlowVoiceCorrectionKit) | Deterministic correction engine and benchmarks |
| In-repo module | `agent-cli` (Rust) | [Repo path](agent-cli) | Local terminal AI agent dispatching helper |
| Reference source | TypeWhisper | [GitHub](https://github.com/TypeWhisper/typewhisper-mac) | Deterministic correction flow + focused observation learning(개념 참고만, source copy 없음) |
| Reference source | FlashText | [GitHub](https://github.com/vi3k6i5/flashtext) | Matching/replacement approach inspiration(runtime reuse 없음) |
| Reference source | JiWER | [GitHub](https://github.com/jitsi/jiwer) | Evaluation and benchmark cross-check reference |
| Reference source | OpenAI Evals | [GitHub](https://github.com/openai/evals) | Benchmark/test-case organization style reference |
| Reference source | LanguageTool | [GitHub](https://github.com/languagetool-org/languagetool) | Error-correction fixture and testing style reference |

### License and Attribution References

| Path | 내용 |
| --- | --- |
| `LICENSE` | Project-level license |
| `SOURCE_ATTRIBUTION.md` | Third-party source references and adaptation scope |
| `MODIFICATIONS.md` | Upstream adaptation notes |
| `Packages/VoxFlowVoiceCorrectionKit/NOTICE.md` | TypeWhisper-derived source licensing |
| `Vendor/` | Vendored runtime license declarations |
| `Package.swift` + `NOTICE/LICENSE` in `Sources/` and `Packages/` | Component dependency and license declarations |

## X에서 만나기

X에서 팔로우해 주세요: [@Counterxing](https://x.com/Counterxing)
