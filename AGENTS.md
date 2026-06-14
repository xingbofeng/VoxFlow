# VoxFlow 项目约定

## 调试与验证

- 默认使用 `make run` 构建并启动真实 macOS App。
- 不使用 `swift run` 代替应用包调试，因为权限、签名和资源加载行为不同。
- 行为改动遵循 TDD：先写失败测试，再做最小实现，最后重构。
- 完成前至少运行 `swift test`、`swift build -c debug -Xswiftc -warnings-as-errors` 和 `make run`。

## 品牌与兼容性

- 中文显示名为“随声写”，英文品牌名为“VoxFlow”。
- 构建产物为 `VoxFlow.app`，安装包为 `VoxFlow-<version>-macOS.dmg`。
- 当前稳定 bundle ID 为 `com.voiceinput.app`，用于保留 macOS 权限和本地调试身份。
- `com.xingbofeng.VoxFlow` 仅用于清理曾短暂生成过的本地调试权限/状态栏记录，不作为当前应用身份。
- `VoiceInput` 仅可用于必要的历史迁移说明、内部 Swift 模块名和兼容路径。
