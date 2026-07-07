// BridgeMode.swift
// 语音桥接模式与运行时选择逻辑。
//
// 为什么要分叉：
// AppGroupBridge 在免费签名 / AltStore / SideStore 真机路径下因为 App Group
// entitlement 不稳定会崩溃或不可用。ClipboardBridge 是当前免费签名真机可验收
// 的降级路径。两条路径必须共存：AppGroupBridge 保留给模拟器和未来付费签名。

import Foundation

/// 用户在诊断页配置的桥接模式。
public enum DictationBridgeMode: String, CaseIterable, Codable, Sendable {
    /// 自动：AppGroup 可用走 AppGroupBridge，不可用降级 ClipboardBridge。
    case automatic
    /// 强制剪贴板：用于 AltStore / SideStore / 免费 Apple ID 真机验收。
    case clipboard
    /// 强制 AppGroup：用于模拟器和未来付费签名验收。
    case appGroup

    public var displayNameKey: String {
        switch self {
        case .automatic: return "bridge_mode.automatic"
        case .clipboard: return "bridge_mode.clipboard"
        case .appGroup: return "bridge_mode.app_group"
        }
    }
}

/// 运行时实际生效的桥接路径。
public enum DictationBridge: String, Equatable, Sendable {
    case appGroupBridge
    case clipboardBridge

    public var displayNameKey: String {
        switch self {
        case .appGroupBridge: return "bridge.effective.app_group"
        case .clipboardBridge: return "bridge.effective.clipboard"
        }
    }
}

/// App Group 可用性结果。
public enum AppGroupAvailability: Equatable, Sendable {
    case available
    case unavailable(reason: Reason)

    public var isAvailable: Bool {
        self == .available
    }

    public var reasonDescription: String? {
        switch self {
        case .available: return nil
        case .unavailable(let reason): return reason.reasonKey
        }
    }

    public enum Reason: String, Equatable, Sendable {
        case suiteNotConfigurable
        case containerLookupFailed
        case entitlementMissing

        public var reasonKey: String {
            switch self {
            case .suiteNotConfigurable: return "bridge.fallback.suite_not_configurable"
            case .containerLookupFailed: return "bridge.fallback.container_lookup_failed"
            case .entitlementMissing: return "bridge.fallback.entitlement_missing"
            }
        }
    }
}

/// 一次桥接选择的快照，供 UI / 诊断 / 键盘共用。
public struct BridgeSelection: Equatable, Sendable {
    public let configuredMode: DictationBridgeMode
    public let effectiveBridge: DictationBridge
    public let appGroupAvailability: AppGroupAvailability
    public let fallbackReason: BridgeFallbackReason?

    public init(
        configuredMode: DictationBridgeMode,
        effectiveBridge: DictationBridge,
        appGroupAvailability: AppGroupAvailability,
        fallbackReason: BridgeFallbackReason?
    ) {
        self.configuredMode = configuredMode
        self.effectiveBridge = effectiveBridge
        self.appGroupAvailability = appGroupAvailability
        self.fallbackReason = fallbackReason
    }
}

/// Auto 模式下从 AppGroup 降级到 Clipboard 的原因（仅记录降级场景）。
public enum BridgeFallbackReason: String, Equatable, Sendable {
    case forcedClipboardMode
    case forcedAppGroupMode
    case autoDegradedToClipboard

    public var reasonKey: String {
        switch self {
        case .forcedClipboardMode: return "bridge.fallback.forced_clipboard"
        case .forcedAppGroupMode: return "bridge.fallback.forced_app_group"
        case .autoDegradedToClipboard: return "bridge.fallback.auto_degraded"
        }
    }
}

/// 纯函数桥接选择器。无 IO，便于单测。
public enum BridgeResolver {
    /// 根据配置模式与 AppGroup 可用性决定生效桥接。
    public static func resolve(
        mode: DictationBridgeMode,
        appGroupAvailability: AppGroupAvailability
    ) -> BridgeSelection {
        switch mode {
        case .clipboard:
            return BridgeSelection(
                configuredMode: .clipboard,
                effectiveBridge: .clipboardBridge,
                appGroupAvailability: appGroupAvailability,
                fallbackReason: .forcedClipboardMode
            )
        case .appGroup:
            // 强制 AppGroup：即使不可用也走 AppGroupBridge，由调用方记录失败。
            // 不静默降级——诊断页要能看出强制模式被卡住。
            return BridgeSelection(
                configuredMode: .appGroup,
                effectiveBridge: .appGroupBridge,
                appGroupAvailability: appGroupAvailability,
                fallbackReason: .forcedAppGroupMode
            )
        case .automatic:
            if appGroupAvailability.isAvailable {
                return BridgeSelection(
                    configuredMode: .automatic,
                    effectiveBridge: .appGroupBridge,
                    appGroupAvailability: appGroupAvailability,
                    fallbackReason: nil
                )
            }
            return BridgeSelection(
                configuredMode: .automatic,
                effectiveBridge: .clipboardBridge,
                appGroupAvailability: appGroupAvailability,
                fallbackReason: .autoDegradedToClipboard
            )
        }
    }
}

/// 持久化 BridgeMode 配置。
///
/// 存储：App Group shared defaults 为主，standard defaults 为镜像兜底。
/// 为什么这样：V1 真机验收以免费签名为主，默认必须直接走 ClipboardBridge，
/// 避免启动时触碰不稳定的 AppGroup。standard defaults 镜像让主 App 自己在
/// AppGroup 不可用时仍能持久化用户选择；未来付费签名后可在诊断页切回 AppGroup。
public enum BridgeModeStore {
    public static let key = "mashangxie.bridgeMode"
    public static let defaultMode: DictationBridgeMode = .clipboard

    /// 读取 BridgeMode。未配置时默认使用 ClipboardBridge。
    public static func read() -> DictationBridgeMode {
        let raw = AppGroup.defaultsIfAvailable?.string(forKey: key)
            ?? UserDefaults.standard.string(forKey: key)
            ?? defaultMode.rawValue
        return DictationBridgeMode(rawValue: raw) ?? defaultMode
    }

    /// 写入 BridgeMode。AppGroup 不可用时只写 standard defaults。
    public static func write(_ mode: DictationBridgeMode) {
        UserDefaults.standard.set(mode.rawValue, forKey: key)
        if let shared = AppGroup.defaultsIfAvailable {
            shared.set(mode.rawValue, forKey: key)
            shared.synchronize()
        }
    }
}

/// 探测 App Group 当前可用性，返回 `AppGroupAvailability`。
/// 供 BridgeResolver 调用方在键盘启动 / 主 App 诊断页使用。
public enum AppGroupProbe {
    /// 探测当前 App Group 状态。任何 IO 异常都视为 unavailable。
    public static func probe() -> AppGroupAvailability {
        guard let defaults = AppGroup.defaultsIfAvailable else {
            return .unavailable(reason: .suiteNotConfigurable)
        }
        // Container lookup is the authoritative signal for entitlement presence.
        guard AppGroup.containerURL != nil else {
            return .unavailable(reason: .containerLookupFailed)
        }
        // Final sanity check: defaults suite responds to write/read.
        let probeKey = "mashangxie.bridgeAvailabilityProbe"
        let probeValue = String(Date().timeIntervalSince1970)
        defaults.set(probeValue, forKey: probeKey)
        defaults.synchronize()
        let readBack = defaults.string(forKey: probeKey)
        defaults.removeObject(forKey: probeKey)
        guard readBack == probeValue else {
            return .unavailable(reason: .entitlementMissing)
        }
        return .available
    }
}

/// 诊断用：最近一次 ClipboardBridge 事件，记录在内存中供诊断页展示。
/// 为什么只放内存：ClipboardBridge 本身就是为了绕开 AppGroup 不可用，
/// 把诊断事件再写回 AppGroup 反而不可靠。主 App / 键盘各自维护一份。
public struct ClipboardBridgeEvent: Equatable, Sendable {
    public let timestamp: Date
    public let kind: Kind

    public enum Kind: String, Equatable, Sendable {
        case deepLinkOpened
        case pasteboardWriteSuccess
        case pasteboardWriteFailed
        case pasteboardReadSuccess
        case pasteboardReadEmpty
        case pasteboardReadFailed
        case inserted
        case dismissed
    }

    public init(timestamp: Date = Date(), kind: Kind) {
        self.timestamp = timestamp
        self.kind = kind
    }
}

/// 进程内 ClipboardBridge 事件总线。键盘和主 App 各持一份。
/// 不跨进程：仅用于诊断页本地展示。
public final class ClipboardBridgeEventLog: @unchecked Sendable {
    public static let shared = ClipboardBridgeEventLog()

    private let lock = NSLock()
    private var events: [ClipboardBridgeEvent] = []

    private init() {}

    public func record(_ event: ClipboardBridgeEvent) {
        lock.withLock {
            events.append(event)
            if events.count > 50 {
                events.removeFirst(events.count - 50)
            }
        }
    }

    public func snapshot() -> [ClipboardBridgeEvent] {
        lock.withLock { events }
    }

    public func clear() {
        lock.withLock { events.removeAll() }
    }
}

/// 诊断快照：当前 BridgeMode 选择结果，供 DiagnosticsView / 键盘诊断展示。
/// 跨进程只读 — 主 App 和键盘各自调用 `BridgeResolver.resolve` 计算后展示。
public struct BridgeDiagnosticsSnapshot: Equatable, Sendable {
    public let configuredMode: DictationBridgeMode
    public let effectiveBridge: DictationBridge
    public let appGroupAvailability: AppGroupAvailability
    public let fallbackReason: BridgeFallbackReason?
    public let lastClipboardEvent: ClipboardBridgeEvent?

    public init(
        configuredMode: DictationBridgeMode,
        effectiveBridge: DictationBridge,
        appGroupAvailability: AppGroupAvailability,
        fallbackReason: BridgeFallbackReason?,
        lastClipboardEvent: ClipboardBridgeEvent?
    ) {
        self.configuredMode = configuredMode
        self.effectiveBridge = effectiveBridge
        self.appGroupAvailability = appGroupAvailability
        self.fallbackReason = fallbackReason
        self.lastClipboardEvent = lastClipboardEvent
    }

    /// Capture current snapshot by probing App Group + reading BridgeModeStore.
    public static func capture() -> BridgeDiagnosticsSnapshot {
        let mode = BridgeModeStore.read()
        let availability = AppGroupProbe.probe()
        let selection = BridgeResolver.resolve(mode: mode, appGroupAvailability: availability)
        let lastEvent = ClipboardBridgeEventLog.shared.snapshot().last
        return BridgeDiagnosticsSnapshot(
            configuredMode: selection.configuredMode,
            effectiveBridge: selection.effectiveBridge,
            appGroupAvailability: selection.appGroupAvailability,
            fallbackReason: selection.fallbackReason,
            lastClipboardEvent: lastEvent
        )
    }
}
