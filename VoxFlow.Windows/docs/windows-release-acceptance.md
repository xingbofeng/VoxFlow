# Windows V1 release acceptance

This checklist is evidence, not a substitute for execution. A row stays
`BLOCKED` until the named environment or hardware was actually used. Do not
claim Windows 10 1809 support from a newer host result.

## Clean Windows 10 1809 x64 VM

| Check | Status | Evidence |
| --- | --- | --- |
| Install unsigned per-user EXE without Python, CUDA, .NET, or VC++ redistributable preinstalled | BLOCKED | No clean 1809 VM attached yet |
| Launch app and open Home/Settings/Models/Voice/Text | BLOCKED | No clean 1809 VM attached yet |
| Render HUD and complete one fixed-WAV/local-model dictation | BLOCKED | No clean 1809 VM attached yet |
| Normal uninstall preserves `%LOCALAPPDATA%\VoxFlow` | BLOCKED | No clean 1809 VM attached yet |
| Reinstall restores settings/history/model state | BLOCKED | No clean 1809 VM attached yet |
| Full-delete uninstall removes `%LOCALAPPDATA%\VoxFlow` after confirmation | BLOCKED | No clean 1809 VM attached yet |

## Host and hardware matrix

| Check | Status | Evidence |
| --- | --- | --- |
| Qwen 0.6B immutable download, prewarm, non-silent canary, fixed WAV | PENDING | |
| Qwen 1.7B immutable download, prewarm, non-silent canary, fixed WAV | PENDING | |
| Built-in microphone | PENDING | |
| USB microphone | BLOCKED | No USB microphone attached yet |
| Notepad quick paste and simulated input | PENDING | |
| Chrome or Edge input | PENDING | |
| VS Code input | PENDING | |
| 100%, 125%, 150%, 200% visual goldens | PENDING | |

Cloud live-smoke evidence is recorded separately in
`docs/live-smoke-evidence-2026-07-11.md`.

## P3 文件转写（当前 Windows 10 19045 主机）

| 检查 | 状态 | 证据 |
| --- | --- | --- |
| MP3、WAV、M4A、AAC、MP4、MOV 首音轨探测与 PCM16/16k/mono 解码 | PASS | 锁定 FFmpeg 对 6 个真实 fixture 的 13 个测试通过 |
| 无音轨视频拒绝、源文件不删除 | PASS | `no-audio.mp4` 真实 fixture 与清理合同测试通过 |
| 开始、取消、继续、从头重试、删除与迟到回调隔离 | PASS | Application 生命周期、run-ID gate 和 WPF 操作矩阵测试通过 |
| 播放/暂停，播放失败不改变任务 | PASS | FFmpeg 受控解码 + NAudio/WASAPI 服务测试通过 |
| OpenAI 全文翻译与失败保留原文 | PASS | pending/running/completed/failed/cancel 测试通过 |
| 六种导出与重启后 SRT | PASS | TXT、Markdown、SRT、译文与双语导出测试通过 |
| 浅/深主题、四档 DPI、10 种页面状态 | PASS | 80 张 WPF 渲染图及感知签名基线通过 |

上述是当前主机的自动化和渲染证据，不替代本文件开头要求的 Windows 10 1809
干净虚拟机安装、卸载和人工交互验收。

## P3 CI 发布证据（2026-07-11）

- GitHub Actions：[`Windows CI` run 29140431490](https://github.com/xingbofeng/VoxFlow/actions/runs/29140431490)，全部门禁通过。
- `VoxFlow-0.1.9-windows-x64-portable.zip`：145,863,520 bytes，SHA-256 `2af293de79925138f85350e37aa8f3f7def1c8639bcedf35f68f65a724347125`。
- `VoxFlow-0.1.9-windows-x64-setup.exe`：101,811,011 bytes，SHA-256 `4a62c30379b10e6d08c0382da278aefaa941f8680483c55b0138a84840860684`。
- `file-transcription-visual-evidence`：80 张 PNG，覆盖浅色/深色、四档 DPI 与 10 种文件转写页面状态。
- 发布脚本内再次通过自包含 x64 publish、凭据扫描、许可证清单、生产 Qwen DLL/ABI、全部 Release 测试、原生依赖布局和 Inno Setup 编译。

这些证据证明 CI 发布产物可生成且布局门禁通过；它们不替代尚未执行的 Windows 10
1809 干净虚拟机安装验收，也不替代 macOS 原生截图对照。
