import Foundation
import VoxFlowModelStore

public struct XASRModelReadinessRunner: Sendable {
    private let streamFactory: any XASRStreamMaking
    private let environment: XASRRuntimePreflight.Environment
    public init(streamFactory: any XASRStreamMaking = XASRRuntime(), environment: XASRRuntimePreflight.Environment = .current()) {
        self.streamFactory = streamFactory
        self.environment = environment
    }
    public func prepare(modelURL: URL) async throws -> ModelPrewarmReport {
        if case .blocked(let blocker) = XASRRuntimePreflight.evaluate(environment: environment) {
            throw XASRProviderError.preflightBlocked(blocker)
        }
        let audio = try Self.canaryAudio()
        let installation = ModelInstallation(modelID: .init(rawValue: "xasr-zh-en-480ms"), version: XASRManifestCatalog.pinnedRevision, installedRoot: modelURL)
        let preparer = XASRCanaryPreparer(factory: streamFactory)
        do {
            let report = try await ModelPrewarmCanaryRunner().prepare(installation: installation, canaryAudio: audio, runtime: preparer)
            if let runtime = streamFactory as? XASRRuntime { await runtime.releaseIdleResources() }
            return report
        } catch {
            await preparer.cancel()
            if let runtime = streamFactory as? XASRRuntime { await runtime.releaseIdleResources() }
            throw error
        }
    }

    private static func canaryAudio() throws -> ModelCanaryAudio {
        guard let url = XASRCanaryResource.url() else {
            throw XASRProviderError.preparationFailed("X-ASR bundled canary is missing.")
        }
        let data = try Data(contentsOf: url)
        guard !data.isEmpty, data.count % 4 == 0 else {
            throw XASRProviderError.preparationFailed("X-ASR canary format is invalid.")
        }
        let samples = data.withUnsafeBytes { bytes in
            (0..<(bytes.count / 4)).map { Float(bitPattern: bytes.loadUnaligned(fromByteOffset: $0 * 4, as: UInt32.self).littleEndian) }
        }
        return ModelCanaryAudio(samples: samples, sampleRate: 16_000, expectedTokens: ["你好", "测试"])
    }
}

/// Resolve the target resource bundle beside the actual app/test executable;
/// no compiler-generated absolute build-directory path can escape into the app.
private enum XASRCanaryResource {
    static func url() -> URL? {
        let codeBundle = Bundle(for: XASRCanaryBundleMarker.self)
        let roots = [
            Bundle.main.resourceURL,
            Bundle.main.bundleURL.deletingLastPathComponent(),
            Bundle.main.executableURL?.deletingLastPathComponent(),
            codeBundle.resourceURL,
            codeBundle.bundleURL.deletingLastPathComponent(),
        ].compactMap { $0 }
        for root in roots {
            let bundles = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
            for bundleURL in bundles where bundleURL.lastPathComponent.hasSuffix("_VoxFlowProviderXASR.bundle") {
                guard let bundle = Bundle(url: bundleURL),
                      let audio = bundle.url(forResource: "xasr-canary", withExtension: "f32") else { continue }
                return audio
            }
        }
        return nil
    }
}

private final class XASRCanaryBundleMarker: NSObject {}

private actor XASRCanaryPreparer: ModelRuntimePreparing {
    let factory: any XASRStreamMaking
    private var stream: (any XASRStreaming)?
    init(factory: any XASRStreamMaking) { self.factory = factory }
    func load(installation: ModelInstallation) async throws { stream = try await factory.makeStream(directoryURL: installation.installedRoot) }
    func compile(installation: ModelInstallation) async throws {
        guard stream != nil else { throw XASRProviderError.invalidSessionState }
    }
    func transcribeCanary(installation: ModelInstallation, audio: ModelCanaryAudio) async throws -> String {
        guard let stream else { throw XASRProviderError.invalidSessionState }
        _ = try await stream.accept(samples: audio.samples, sampleRate: audio.sampleRate)
        let result = XASRTextFormatter.format(try await stream.finish())
        self.stream = nil
        return result
    }
    func cancel() async { await stream?.cancel(); stream = nil }
}
