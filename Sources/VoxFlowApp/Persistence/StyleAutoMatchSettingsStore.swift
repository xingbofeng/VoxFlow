import Foundation

/// `SettingsRepository`-backed storage for the global style auto-match controls
/// owned by the `配置自动匹配` Sheet (OpenSpec `style-auto-routing` §4.6).
///
/// Persists the global AI 智能挑选 switch, context-round settings, and the
/// lightweight route cache used by the style router.
struct StyleAutoMatchSettings: Equatable, Codable, Sendable {
    /// 全局 AI 智能挑选开关。`false` 时所有 style 都不会进入 AI router，
    /// 优先级仅保留手动 App 规则 + default style。
    var globalEnabled: Bool = true

    /// 同 App context rounds 设置。默认开启，保留最近 3 轮 / 6 小时。
    var contextRounds: ContextRoundsSettings = .defaults

    var routeCacheTTLHours: Int = 24

    /// 第一版 route cache。key 使用规范化 bundleID；无 bundleID 时使用
    /// 规范化 appName。仅保存 styleID 和过期信息，不保存用户正文。
    var routeCache: [String: StyleRouteCacheEntry] = [:]

    init(
        globalEnabled: Bool = true,
        contextRounds: ContextRoundsSettings = .defaults,
        routeCacheTTLHours: Int = 24,
        routeCache: [String: StyleRouteCacheEntry] = [:]
    ) {
        self.globalEnabled = globalEnabled
        self.contextRounds = contextRounds
        self.routeCacheTTLHours = max(1, routeCacheTTLHours)
        self.routeCache = routeCache
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.globalEnabled = try c.decodeIfPresent(Bool.self, forKey: .globalEnabled) ?? true
        self.contextRounds = try c.decodeIfPresent(ContextRoundsSettings.self, forKey: .contextRounds) ?? .defaults
        self.routeCacheTTLHours = max(1, try c.decodeIfPresent(Int.self, forKey: .routeCacheTTLHours) ?? 24)
        self.routeCache = try c.decodeIfPresent([String: StyleRouteCacheEntry].self, forKey: .routeCache) ?? [:]
    }

    enum CodingKeys: String, CodingKey {
        case globalEnabled
        case contextRounds
        case routeCacheTTLHours
        case routeCache
    }
}

struct ContextRoundsSettings: Equatable, Codable, Sendable {
    static let defaults = ContextRoundsSettings(enabled: true, maxRounds: 3, ttlHours: 6)

    var enabled: Bool
    var maxRounds: Int
    var ttlHours: Int

    init(enabled: Bool = true, maxRounds: Int = 3, ttlHours: Int = 6) {
        self.enabled = enabled
        self.maxRounds = max(0, min(maxRounds, 5))
        self.ttlHours = max(1, min(ttlHours, 24))
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            enabled: try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true,
            maxRounds: try c.decodeIfPresent(Int.self, forKey: .maxRounds) ?? 3,
            ttlHours: try c.decodeIfPresent(Int.self, forKey: .ttlHours) ?? 6
        )
    }
}

struct StyleRouteCacheEntry: Equatable, Codable, Sendable {
    let styleID: String
    let source: String
    let createdAt: Date
    var lastUsedAt: Date
    let expiresAt: Date
    var hitCount: Int

    var isExpired: Bool {
        expiresAt <= Date()
    }

    func isExpired(at now: Date) -> Bool {
        expiresAt <= now
    }
}

final class StyleAutoMatchSettingsStore {
    static let settingsKey = "style.autoMatch.settings"

    private let settingsRepository: any SettingsRepository

    init(settingsRepository: any SettingsRepository) {
        self.settingsRepository = settingsRepository
    }

    func load() -> StyleAutoMatchSettings {
        guard let json = try? settingsRepository.value(forKey: Self.settingsKey),
              let data = json.data(using: .utf8) else {
            return StyleAutoMatchSettings()
        }
        return (try? JSONDecoder().decode(StyleAutoMatchSettings.self, from: data))
            ?? StyleAutoMatchSettings()
    }

    func save(_ settings: StyleAutoMatchSettings) throws {
        let data = try JSONEncoder().encode(settings)
        try settingsRepository.set(
            Self.settingsKey,
            jsonValue: String(data: data, encoding: .utf8) ?? "{}"
        )
    }

    func update(_ mutate: (inout StyleAutoMatchSettings) -> Void) throws {
        var settings = load()
        mutate(&settings)
        try save(settings)
    }
}
