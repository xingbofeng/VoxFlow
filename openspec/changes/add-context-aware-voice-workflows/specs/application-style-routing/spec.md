# Delta: 应用风格路由

**Change ID:** `add-context-aware-voice-workflows`
**Affects:** 应用扫描、风格规则、LLM 配置、风格设置页

## ADDED Requirements

### Requirement: 扫描本机已安装应用

系统 SHALL 在用户主动开始智能配置时扫描标准 macOS 应用目录，并返回应用名称、Bundle ID、图标、路径和可用系统分类。

#### Scenario: 扫描标准应用目录

- GIVEN 用户已经进入智能配置流程
- WHEN 系统扫描 `/Applications`、`~/Applications` 和系统应用目录
- THEN 结果按 Bundle ID 和规范化路径去重
- AND 扫描不读取用户文档或应用内容

#### Scenario: 应用缺少 Bundle ID

- GIVEN 扫描到一个缺少 Bundle ID 的 `.app`
- WHEN 系统构建应用列表
- THEN 该应用仍可显示并允许用户手动选择
- AND 它不得参与 Bundle ID 精确匹配

### Requirement: 内置高频应用注册表

系统 SHALL 使用数据驱动注册表为高频应用提供默认风格建议，且注册表不承担完整应用目录职责。

#### Scenario: 注册表命中

- GIVEN 已安装应用的 Bundle ID 命中内置注册表
- WHEN 系统构建推荐
- THEN 直接使用注册表中的建议风格
- AND 推荐来源显示为“系统预设”
- AND 不为该应用调用 LLM 分类

#### Scenario: 终端应用默认建议

- GIVEN 已安装应用为 Terminal、iTerm 或 Ghostty
- WHEN 系统构建推荐
- THEN 建议风格为 `builtin.coding`

### Requirement: LLM 批量分类未知应用

系统 SHALL 只将未命中注册表的应用元数据批量交给已配置 LLM，并限制返回值为当前启用风格。

#### Scenario: 批量分类

- GIVEN LLM 已配置并通过连接测试
- AND 存在未命中注册表的应用
- WHEN 用户开始智能配置
- THEN 请求只包含应用名称、Bundle ID 和系统分类
- AND 模型只能返回候选 style ID
- AND 成功结果标记为“AI 推荐”

#### Scenario: 返回非法风格

- GIVEN LLM 返回不存在或未启用的 style ID
- WHEN 系统解析分类结果
- THEN 忽略该项分类
- AND 不为该应用生成推荐或保存应用规则
- AND 该应用在运行时仍可使用当前默认风格兜底

#### Scenario: 分类失败

- GIVEN LLM 请求超时或失败
- WHEN 系统完成推荐流程
- THEN 注册表结果仍然可预览
- AND 未分类应用保持未配置，不生成默认风格建议
- AND 未分类应用在运行时仍可使用当前默认风格兜底
- AND 普通语音转录保持可用

### Requirement: 推荐确认后才生效

系统 SHALL 在用户确认前将扫描和分类结果视为临时推荐，不得改变运行时应用规则。

#### Scenario: 用户取消推荐

- GIVEN 智能配置预览已经生成
- WHEN 用户取消或关闭预览
- THEN 当前 `AppStyleRuleStore` 保持不变

#### Scenario: 用户确认推荐

- GIVEN 用户已经调整推荐结果
- WHEN 用户点击“应用配置”
- THEN 系统以一次确认操作保存最终规则
- AND 每个应用最多绑定一个风格

### Requirement: 规则优先级

系统 SHALL 按用户确认规则、内置建议和默认风格的确定顺序选择运行时风格。

#### Scenario: 用户规则覆盖注册表

- GIVEN 注册表将某应用建议为风格 A
- AND 用户已将该应用绑定到风格 B
- WHEN 该应用中开始普通转录
- THEN 使用风格 B

#### Scenario: 未知应用

- GIVEN 应用没有用户规则且未命中注册表
- WHEN LLM 分类不可用
- THEN 使用当前默认风格

### Requirement: LLM 配置成功后的智能配置邀请

系统 SHALL 在用户首次完成 LLM 配置并通过连接测试后提供一次可跳过的智能配置邀请。

#### Scenario: 首次成功配置

- GIVEN 用户此前未处理过智能配置邀请
- WHEN LLM 连接测试首次成功
- THEN 显示“智能配置应用”邀请
- AND 提供“暂不设置”和“开始扫描”

#### Scenario: 已处理邀请

- GIVEN 用户已经开始扫描或选择暂不设置
- WHEN 后续再次测试 LLM 成功
- THEN 不重复自动弹出邀请
- AND 风格页仍提供手动入口

### Requirement: 在风格中管理适用应用

系统 SHALL 在每个风格详情中展示并管理适用应用。

#### Scenario: 添加已安装应用

- GIVEN 用户打开某个风格的“选择应用”
- WHEN 用户搜索并添加一个已安装应用
- THEN 应用显示在该风格的适用应用列表
- AND 若它原属于其他风格，则解除旧绑定

#### Scenario: 重新扫描

- GIVEN 用户已有手动规则
- WHEN 用户重新扫描应用
- THEN 手动规则不会被系统预设或 AI 推荐静默覆盖

## MODIFIED Requirements

### Requirement: 应用风格选择

普通语音转录 SHALL 继续在录音开始时锁定目标应用，并使用已确认应用规则选择风格。

#### Scenario: 录音期间切换应用

- GIVEN 用户在应用 A 开始录音
- WHEN 用户录音期间切换到应用 B
- THEN 文本处理仍使用应用 A 在开始时锁定的风格

## REMOVED Requirements

(None)
