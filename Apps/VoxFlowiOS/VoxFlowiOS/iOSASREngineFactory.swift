import Foundation
import VoxFlowASRRuntime
import VoxFlowProviderTencentCloud
import VoxFlowProviderAliyunDashScope
import VoxFlowProviderVolcengine

/// 根据本地凭证构建共享 `ASREngine`。
///
/// macOS 的 ASRManager 依赖 VoxFlowApp 内部大量装配；iOS V1 只复用共享 runtime 的
/// `CloudRealtimeASREngine` + 三家云 provider 的 streaming client，配置由本地凭证文件生成。
enum iOSASREngineFactory {
    enum FactoryError: LocalizedError {
        case missingCredential(provider: String)
        case unsupportedProvider(String)

        var errorDescription: String? {
            switch self {
            case let .missingCredential(provider):
                return "\(provider) 凭证不完整，请在服务页填写。"
            case let .unsupportedProvider(provider):
                return "不支持的 Provider：\(provider)"
            }
        }
    }

    static func makeTencentEngine(store: LocalCredentialStore) throws -> ASREngine {
        let values = store.effectiveValues(for: .tencent)
        guard store.isEffectivelyComplete(.tencent) else {
            throw FactoryError.missingCredential(provider: "腾讯云")
        }
        let configurationProvider: @Sendable () throws -> TencentRealtimeASRConfiguration = {
            TencentRealtimeASRConfiguration(
                appID: values["appID"] ?? "",
                secretID: values["secretID"] ?? "",
                secretKey: values["secretKey"] ?? ""
            )
        }
        let client = TencentRealtimeASRClient()
        let logger = OSLogASRSessionLogger()
        return CloudRealtimeASREngine(
            client: client,
            logger: logger,
            logLabel: "TencentRealtimeASREngine",
            sessionIDPrefix: "tencent-asr",
            configurationProvider: configurationProvider,
            isConfigurationComplete: { $0.isComplete },
            missingConfigurationError: { TencentRealtimeASRError.missingCredential },
            inconsistentSampleRateError: { _ in TencentRealtimeASRError.inconsistentSampleRate },
            unsupportedSampleRateError: { TencentRealtimeASRError.unsupportedSampleRate($0) },
            interpretMessage: { message, state in
                let text = message.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    if message.isStable, let index = message.index {
                        state.stableSegments[index] = text
                        state.latestText = CloudRealtimeASRTranscriptAssembler.joinedStablePrefix(state.stableSegments)
                    } else {
                        state.latestText = CloudRealtimeASRTranscriptAssembler.combine(
                            stablePrefix: CloudRealtimeASRTranscriptAssembler.joinedStablePrefix(state.stableSegments),
                            liveText: text
                        )
                    }
                }
                if message.isFinal {
                    return state.latestText.isEmpty ? nil : CloudRealtimeASREmission(text: state.latestText, isFinal: true)
                }
                return text.isEmpty ? nil : CloudRealtimeASREmission(text: state.latestText, isFinal: false)
            }
        )
    }

    static func makeAliyunEngine(store: LocalCredentialStore) throws -> ASREngine {
        let values = store.effectiveValues(for: .aliyun)
        guard store.isEffectivelyComplete(.aliyun) else {
            throw FactoryError.missingCredential(provider: "阿里云 DashScope")
        }
        let configurationProvider: @Sendable () throws -> AliyunDashScopeRealtimeASRConfiguration = {
            AliyunDashScopeRealtimeASRConfiguration(apiKey: values["apiKey"] ?? "")
        }
        let client = AliyunDashScopeRealtimeASRClient()
        let logger = OSLogASRSessionLogger()
        return CloudRealtimeASREngine(
            client: client,
            logger: logger,
            logLabel: "AliyunDashScopeRealtimeASREngine",
            sessionIDPrefix: "aliyun-dashscope-asr",
            configurationProvider: configurationProvider,
            isConfigurationComplete: { $0.isComplete },
            missingConfigurationError: { AliyunDashScopeRealtimeASRError.missingCredential },
            inconsistentSampleRateError: { _ in AliyunDashScopeRealtimeASRError.inconsistentSampleRate },
            unsupportedSampleRateError: { AliyunDashScopeRealtimeASRError.unsupportedSampleRate($0) },
            interpretMessage: { message, state in
                if message.event == .taskFinished {
                    return state.latestText.isEmpty ? nil : CloudRealtimeASREmission(text: state.latestText, isFinal: true)
                }
                guard message.event == .resultGenerated, !message.isHeartbeat else { return nil }
                let text = message.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    state.latestText = CloudRealtimeASRTranscriptAssembler.combine(prefix: state.committedText, text: text)
                    if message.isFinalResult {
                        state.committedText = state.latestText
                    }
                }
                return text.isEmpty ? nil : CloudRealtimeASREmission(text: state.latestText, isFinal: false)
            }
        )
    }

    static func makeVolcengineEngine(store: LocalCredentialStore) throws -> ASREngine {
        let values = store.effectiveValues(for: .volcengine)
        guard store.isEffectivelyComplete(.volcengine) else {
            throw FactoryError.missingCredential(provider: "火山云")
        }
        let configurationProvider: @Sendable () throws -> VolcengineRealtimeASRConfiguration = {
            VolcengineRealtimeASRConfiguration(
                appID: values["appID"] ?? "",
                accessToken: values["accessToken"] ?? "",
                secretKey: values["secretKey"] ?? ""
            )
        }
        let client = VolcengineRealtimeASRClient()
        let logger = OSLogASRSessionLogger()
        return CloudRealtimeASREngine(
            client: client,
            logger: logger,
            logLabel: "VolcengineRealtimeASREngine",
            sessionIDPrefix: "volcengine-asr",
            configurationProvider: configurationProvider,
            isConfigurationComplete: { $0.isComplete },
            missingConfigurationError: { VolcengineRealtimeASRError.missingCredential },
            inconsistentSampleRateError: { _ in VolcengineRealtimeASRError.inconsistentSampleRate },
            unsupportedSampleRateError: { VolcengineRealtimeASRError.unsupportedSampleRate($0) },
            interpretMessage: { message, state in
                let text = message.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    state.latestText = text
                }
                if message.isFinal {
                    return state.latestText.isEmpty ? nil : CloudRealtimeASREmission(text: state.latestText, isFinal: true)
                }
                return text.isEmpty ? nil : CloudRealtimeASREmission(text: state.latestText, isFinal: false)
            }
        )
    }
}
