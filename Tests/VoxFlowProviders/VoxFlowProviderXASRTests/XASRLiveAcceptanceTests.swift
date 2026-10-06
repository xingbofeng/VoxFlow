import Foundation
import VoxFlowASRCore
import VoxFlowAudio
import VoxFlowModelStore
import XCTest
@testable import VoxFlowProviderXASR

/// Explicitly opted-in real weights; never silently converted to a fake test.
final class XASRLiveAcceptanceTests: XCTestCase, @unchecked Sendable {
    func testVerifiedCachedAssetsInstallThroughModelStoreAndPassRealCanary() async throws {
        guard let cache = ProcessInfo.processInfo.environment["VOICEINPUT_TEST_XASR_MODEL_DIR"] else {
            throw XCTSkip("Set VOICEINPUT_TEST_XASR_MODEL_DIR to verified native assets")
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("voxflow-xasr-install-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let manifest = try XASRManifestCatalog.modelStoreManifest()
        let stage = ResumableModelDownloader.stagingRoot(for: XASRManifestCatalog.modelInstallKey, storeRoot: root)
        try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: true)
        for component in manifest.components {
            try FileManager.default.copyItem(at: URL(fileURLWithPath: cache).appendingPathComponent(component.localPath), to: stage.appendingPathComponent(component.localPath))
        }
        let installer = XASRModelStoreDownloader(storeRoot: root)
        let installed = try await installer.download { _ in }
        XCTAssertEqual(installed, XASRModel.defaultDirectoryURL(modelsDirectory: root))
        XCTAssertTrue(try ModelIntegrityValidator().validate(manifest: manifest, installedRoot: installed, runtimeVersion: XASRManifestCatalog.runtimeVersion).isValid)
        let runtime = XASRRuntime()
        let canary = try await XASRModelReadinessRunner(streamFactory: runtime).prepare(modelURL: installed)
        XCTAssertTrue(canary.isReady)
        XCTAssertTrue(canary.transcript.contains("你好"))
        XCTAssertTrue(canary.transcript.contains("测试"))
        let repeatedInstall = try await installer.download { _ in }
        XCTAssertEqual(repeatedInstall, installed)
        await runtime.invalidate()
    }

    func testRealSessionUsesIncrementalPartialsAndFlushesLastWord() async throws {
        guard let model = ProcessInfo.processInfo.environment["VOICEINPUT_TEST_XASR_MODEL_DIR"],
              let pcm = ProcessInfo.processInfo.environment["VOICEINPUT_TEST_XASR_PCM"] else {
            throw XCTSkip("Set VOICEINPUT_TEST_XASR_MODEL_DIR and VOICEINPUT_TEST_XASR_PCM")
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: pcm))
        let samples = data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        let runtime = XASRRuntime()
        let provider = XASRASRProvider(descriptor: XASRProviderDescriptor.descriptor(modelInstallationState: .ready), modelURL: URL(fileURLWithPath: model), streamFactory: runtime)
        let session = try await provider.makeSession(language: .init(bcp47Tag: "zh-CN"))
        let events = Task { () -> [ASREvent] in
            var result: [ASREvent] = []; for await event in session.events { result.append(event) }; return result
        }
        try await session.start()
        for (index, offset) in stride(from: 0, to: samples.count, by: 1_600).enumerated() {
            try await session.accept(AudioFrame(sequenceNumber: UInt64(index), startSample: UInt64(offset), samples: ContiguousArray(samples[offset..<min(offset + 1_600, samples.count)]), sampleRate: 16_000, capturedAt: .now))
        }
        try await session.finish()
        await session.cancel()
        let delivered = await events.value
        let final = delivered.compactMap { event -> String? in if case .final(_, _, let text) = event { return text }; return nil }
        XCTAssertEqual(final.count, 1)
        XCTAssertTrue(final[0].hasSuffix("星期三"))
        XCTAssertTrue(delivered.contains { if case .partial = $0 { return true }; return false })
        let metrics = delivered.compactMap { event -> ASRMetrics? in if case .metrics(_, _, let metrics) = event { return metrics }; return nil }.first
        XCTAssertEqual(metrics?.droppedFrameCount, 0)
        XCTAssertEqual(metrics?.audioDuration, .nanoseconds(Int64(samples.count) * 1_000_000_000 / 16_000))
        await runtime.invalidate()
    }
}
