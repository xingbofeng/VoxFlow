import Foundation
import VoxFlowTextProcessing

extension Notification.Name {
    /// 恢复默认设置成功后广播，相关 ViewModel（如 `StyleViewModel`）监听以重新加载
    /// 风格列表与自动匹配设置，使可见 UI 立即反映默认状态。
    static let settingsDidRestoreDefaults = Notification.Name("VoxFlow.SettingsDidRestoreDefaults")
}

/// 恢复默认设置服务（OpenSpec `restore-default-settings`）。
///
/// 集中编排 settings repository、风格 repository、快捷键/语言/ASR/开机启动等
/// 偏好 store，按 allowlist 精确重置「受管偏好」，并保留 Provider 配置、
/// 凭据、历史/词汇/自定义风格等用户资产。无 SwiftUI 依赖，便于用 repository fake
/// 或临时 SQLite 做边界测试。
///
/// 设计约束（见 `openspec/changes/restore-default-settings/design.md`）：
/// - 禁止 blanket 删除 `app_settings` 全表或按前缀删除未知 key；只删除受管 key。
/// - 内置风格按 `BuiltInStyleCatalog` 当前版本覆盖；自定义风格保留。
/// - 界面语言、Provider 默认选择、Provider 凭据不得触碰。
@MainActor
final class SettingsDefaultRestoreService {
    private let settingsRepository: any SettingsRepository
    private let styleRepository: any StyleRepository
    private let shortcutManager: ShortcutManager
    private let languageManager: LanguageManager
    private let asrSettingsResetter: (any ASRSettingsResetting)?
    private let launchAtLoginManager: any LaunchAtLoginManaging
    private let clock: any AppClock

    init(
        settingsRepository: any SettingsRepository,
        styleRepository: any StyleRepository,
        shortcutManager: ShortcutManager,
        languageManager: LanguageManager,
        asrSettingsResetter: (any ASRSettingsResetting)?,
        launchAtLoginManager: any LaunchAtLoginManaging,
        clock: any AppClock
    ) {
        self.settingsRepository = settingsRepository
        self.styleRepository = styleRepository
        self.shortcutManager = shortcutManager
        self.languageManager = languageManager
        self.asrSettingsResetter = asrSettingsResetter
        self.launchAtLoginManager = launchAtLoginManager
        self.clock = clock
    }

    /// 受管偏好 key 清单。只删除这些 key，删除后各 store 的 load() 回落到默认值。
    static var managedSettingsKeys: [String] {
        var keys: [String] = []
        keys.append(contentsOf: SettingsKey.all)
        keys.append(contentsOf: SettingsSystemOption.allCases.map(\.rawValue))
        keys.append(contentsOf: VoiceCorrectionSettingsKey.allCases.map(\.rawValue))
        keys.append(DeterministicTextProcessingSettingsStore.settingsKey)
        keys.append(StyleAutoMatchSettingsStore.settingsKey)
        return keys
    }

    /// 执行恢复默认设置。任何步骤抛错即向上抛出，调用方负责反馈与刷新。
    func restoreDefaultSettings() throws {
        // 1. 按受管 key 清单删除偏好，保留未知 key 与 Provider/凭证/历史等用户资产。
        for key in Self.managedSettingsKeys {
            // key 可能不存在；删除失败仅在真实 I/O 错误时抛出。
            if (try? settingsRepository.value(forKey: key)) != nil {
                try settingsRepository.deleteValue(forKey: key)
            }
        }

        // 2. 快捷键恢复默认（UserDefaults）。
        shortcutManager.resetToDefaults()

        // 3. 识别语言恢复默认（界面语言保留）。
        languageManager.setLanguage(.default)

        // 4. ASR 引擎/模型偏好恢复默认；Provider 凭据保留。
        asrSettingsResetter?.resetASRSettingsToDefaults()

        // 5. 开机启动恢复默认（关闭）。settingsRepository 中的镜像 key 已在 allowlist 中删除。
        try launchAtLoginManager.setEnabled(false)

        // 6. 内置风格按当前版本 catalog 覆盖（prompt/元数据/输出格式/自动匹配/温度/启用/默认）。
        //    自定义风格（非内置 ID）不删除、不改写。
        try restoreBuiltInStyles()
    }

    private func restoreBuiltInStyles() throws {
        let now = clock.now
        let catalogProfiles = BuiltInStyleCatalog.profiles(now: now)
        for profile in catalogProfiles {
            try styleRepository.save(profile)
        }
    }
}
