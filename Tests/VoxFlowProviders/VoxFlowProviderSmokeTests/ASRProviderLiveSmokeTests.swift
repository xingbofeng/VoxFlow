import XCTest
import VoxFlowASRCore
import VoxFlowProviderApple
import VoxFlowProviderFunASR
import VoxFlowProviderNVIDIA
import VoxFlowProviderParaformer
import VoxFlowProviderQwen3
import VoxFlowProviderSenseVoice
import VoxFlowProviderWhisper

final class ASRProviderLiveSmokeTests: XCTestCase {
    func testConfiguredProviderRunsMinimalSmokeCorpus() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let providerID = environment["VOICEINPUT_TEST_ASR_SMOKE_PROVIDER"] else {
            throw XCTSkip("Set VOICEINPUT_TEST_ASR_SMOKE_PROVIDER to apple, qwen3, whisper, funasr, sensevoice, paraformer, or nvidia.")
        }
        let provider = try await makeProvider(providerID: providerID, environment: environment)
        let manifest = try ASRSmokeManifest.loadDefault()
        let runner = ASRSmokeRunner()
        let prompt = environment["VOICEINPUT_TEST_ASR_SMOKE_PROMPT"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        var results: [ASRSmokeResult] = []
        for sample in manifest.samples {
            results.append(try await runner.run(
                sample: sample,
                provider: provider,
                prompt: prompt?.isEmpty == false ? prompt : nil
            ))
        }
        try writeResultsIfRequested(
            results: zip(manifest.samples, results).map { ($0.0, $0.1) },
            providerID: providerID,
            environment: environment
        )

        let failed = results.filter { $0.outcome == .failed }
        XCTAssertTrue(
            failed.isEmpty,
            failed.map { "\($0.providerID)/\($0.sampleID): \($0.issues.map(\.rawValue).joined(separator: ","))" }
                .joined(separator: "\n")
        )
    }

    private func makeProvider(
        providerID: String,
        environment: [String: String]
    ) async throws -> any ASRProvider {
        switch providerID {
        case "apple", "apple-speech":
            let provider = AppleSpeechASRProvider()
            let health = await provider.healthCheck()
            guard case .healthy = health else {
                if case let .unhealthy(error) = health {
                    throw XCTSkip("Apple Speech is not authorized or available for live smoke: \(error.message)")
                }
                throw XCTSkip("Apple Speech is not authorized or available for live smoke.")
            }
            return provider
        case "qwen3":
            let modelURL = try modelURL(environment["VOICEINPUT_TEST_QWEN3_MODEL_PATH"], providerID: providerID)
            let variant: Qwen3ModelVariant = environment["VOICEINPUT_TEST_QWEN3_VARIANT"] == "1.7b"
                ? .qwen17SpeechSwift8Bit
                : .qwen06SpeechSwift4Bit
            return Qwen3ASRProvider(
                descriptor: Qwen3ProviderDescriptor.descriptor(
                    modelInstallationState: .ready,
                    variant: variant
                ),
                modelURL: modelURL,
                sessionFactory: Qwen3StreamingSessionFactoryProvider.factory(for: variant)
            )
        case "whisper":
            let modelURL = try modelURL(environment["VOICEINPUT_TEST_WHISPERKIT_MODEL_PATH"], providerID: providerID)
            let variant = Self.whisperVariant(environment["VOICEINPUT_TEST_WHISPERKIT_VARIANT"])
            return WhisperASRProvider(
                descriptor: WhisperProviderDescriptor.descriptor(
                    variant: variant,
                    modelInstallationState: .ready
                ),
                variant: variant,
                modelURL: modelURL
            )
        case "funasr":
            let modelURL = try modelURL(environment["VOICEINPUT_TEST_FUNASR_MODEL_PATH"], providerID: providerID)
            let variant = FunASRModelVariant(rawValue: environment["VOICEINPUT_TEST_FUNASR_VARIANT"] ?? "int8") ?? .int8
            return FunASRASRProvider(
                descriptor: FunASRProviderDescriptor.descriptor(
                    precision: variant,
                    modelInstallationState: .ready
                ),
                variant: variant,
                modelURL: modelURL
            )
        case "paraformer":
            let modelURL = try modelURL(environment["VOICEINPUT_TEST_PARAFORMER_MODEL_PATH"], providerID: providerID)
            return ParaformerASRProvider(
                descriptor: ParaformerProviderDescriptor.descriptor(modelInstallationState: .ready),
                modelURL: modelURL
            )
        case "nvidia", "nvidia-nemotron":
            let modelURL = try modelURL(environment["VOICEINPUT_TEST_NVIDIA_NEMOTRON_MODEL_PATH"], providerID: providerID)
            return NVIDIANemotronASRProvider.live(
                descriptor: NVIDIANemotronProviderDescriptor.descriptor(modelInstallationState: .ready),
                modelURL: modelURL
            )
        case "sensevoice":
            let modelURL = try modelURL(environment["VOICEINPUT_TEST_SENSEVOICE_MODEL_PATH"], providerID: providerID)
            return SenseVoiceASRProvider(
                descriptor: SenseVoiceProviderDescriptor.descriptor(modelInstallationState: .ready),
                modelURL: modelURL
            )
        default:
            throw XCTSkip("Unknown VOICEINPUT_TEST_ASR_SMOKE_PROVIDER value: \(providerID).")
        }
    }

    private static func whisperVariant(_ rawValue: String?) -> WhisperKitModelVariant {
        switch rawValue?.lowercased() {
        case "large-v3", "largev3", "large_v3":
            return .largeV3
        default:
            return .turbo
        }
    }

    private func modelURL(_ rawPath: String?, providerID: String) throws -> URL {
        guard let rawPath, !rawPath.isEmpty else {
            throw XCTSkip("Set model path env for \(providerID) before running ASR live smoke.")
        }
        return URL(fileURLWithPath: rawPath)
    }

    private func writeResultsIfRequested(
        results: [(ASRSmokeSample, ASRSmokeResult)],
        providerID: String,
        environment: [String: String]
    ) throws {
        guard let outputPath = environment["VOICEINPUT_TEST_ASR_SMOKE_OUTPUT"],
              !outputPath.isEmpty else {
            return
        }
        let payload = results.map { sample, result in
            let audioDurationMs = audioDurationMilliseconds(for: sample)
            let latencyMs = result.finalLatencyMilliseconds
            let rtf = latencyMs.flatMap { latency in
                audioDurationMs > 0 ? Double(latency) / Double(audioDurationMs) : nil
            }
            return SmokeOutputItem(
                id: sample.id,
                provider: providerID,
                language: sample.language,
                audioPath: sample.audioPath,
                status: result.outcome == .passed ? "completed" : result.outcome.rawValue.lowercased(),
                finalText: result.finalText,
                latencyMs: latencyMs,
                rtf: rtf,
                issues: result.issues.map(\.rawValue)
            )
        }
        let data = try JSONEncoder().encode(payload)
        let url = URL(fileURLWithPath: outputPath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url)
    }

    private func audioDurationMilliseconds(for sample: ASRSmokeSample) -> Int {
        guard let frames = try? ASRSmokeAudio.loadFrames(for: sample),
              let sampleRate = frames.first?.sampleRate,
              sampleRate > 0 else {
            return 0
        }
        let sampleCount = frames.reduce(0) { $0 + $1.samples.count }
        return Int((Double(sampleCount) / Double(sampleRate)) * 1_000)
    }

    private static func repositoryRoot() throws -> URL {
        var directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        while directory.path != "/" {
            if FileManager.default.fileExists(
                atPath: directory.appendingPathComponent("Package.swift").path
            ) {
                return directory
            }
            directory.deleteLastPathComponent()
        }
        throw NSError(
            domain: "ASRProviderLiveSmokeTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Could not locate repository root."]
        )
    }
}

private struct SmokeOutputItem: Encodable {
    let id: String
    let provider: String
    let language: String
    let audioPath: String
    let status: String
    let finalText: String
    let latencyMs: Int?
    let rtf: Double?
    let issues: [String]
}
