import XCTest
@testable import VoxFlowApp

@MainActor
final class CapabilityModelViewModelTests: XCTestCase {
    func testTTSModelCatalogContainsConfirmedSoniqoModelsWithKokoroRecommended() {
        let viewModel = CapabilityModelViewModel(kind: .tts)

        XCTAssertEqual(
            viewModel.models.map(\.id),
            [
                CapabilityModelID.systemDefaultTTS,
                CapabilityModelID.kokoroTTS,
                CapabilityModelID.qwen3TTS06B4Bit,
                CapabilityModelID.cosyVoice3,
            ]
        )
        XCTAssertEqual(viewModel.models.first?.displayName, "系统默认")
        XCTAssertTrue(viewModel.models.first?.isRecommended == true)
        XCTAssertEqual(viewModel.selectedModelID, CapabilityModelID.systemDefaultTTS)
    }

    func testTranslationModelCatalogContainsSystemLLMAndMADLADOptions() {
        let viewModel = CapabilityModelViewModel(kind: .translation)

        XCTAssertEqual(
            viewModel.models.map(\.id),
            [
                CapabilityModelID.llmTranslation,
                CapabilityModelID.systemDefaultTranslation,
                CapabilityModelID.madladTranslation,
            ]
        )
        XCTAssertEqual(viewModel.models.first?.displayName, "智能模型配置")
        XCTAssertEqual(viewModel.selectedModelID, CapabilityModelID.llmTranslation)
        XCTAssertEqual(
            viewModel.models.first(where: { $0.id == CapabilityModelID.systemDefaultTranslation })?.fallbackDescription,
            "Apple 系统翻译暂不可用"
        )
        XCTAssertEqual(
            viewModel.models.first(where: { $0.id == CapabilityModelID.llmTranslation })?.displayName,
            "智能模型配置"
        )
        XCTAssertEqual(
            viewModel.models.first(where: { $0.id == CapabilityModelID.llmTranslation })?.isInstalled,
            true
        )
    }

    func testDownloadMarksModelInstalledAndPublishesProgress() async {
        let downloader = CapturingCapabilityModelDownloader()
        let viewModel = CapabilityModelViewModel(kind: .tts, downloader: downloader)

        await viewModel.downloadModel(id: CapabilityModelID.kokoroTTS)

        XCTAssertEqual(downloader.downloadedIDs, [CapabilityModelID.kokoroTTS])
        XCTAssertFalse(viewModel.isDownloading)
        XCTAssertNil(viewModel.downloadingModelID)
        XCTAssertEqual(viewModel.downloadProgress, 1.0)
        XCTAssertEqual(
            viewModel.models.first(where: { $0.id == CapabilityModelID.kokoroTTS })?.isInstalled,
            true
        )
        XCTAssertEqual(viewModel.lastActionMessage, "本地模型下载完成")
        XCTAssertNil(viewModel.lastError)
    }

    func testDownloadIgnoresRepeatedRequestsWhileDownloadIsInFlight() async {
        let downloader = SuspendingCapabilityModelDownloader()
        let viewModel = CapabilityModelViewModel(kind: .tts, downloader: downloader)

        let first = Task { await viewModel.downloadModel(id: CapabilityModelID.kokoroTTS) }
        await downloader.waitUntilStarted()
        await viewModel.downloadModel(id: CapabilityModelID.kokoroTTS)

        XCTAssertEqual(downloader.downloadedIDs(), [CapabilityModelID.kokoroTTS])
        downloader.finish()
        await first.value
    }

    func testSelectedModelPersistsPerCapabilityKind() {
        let suiteName = "test.CapabilityModelViewModel.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let ttsViewModel = CapabilityModelViewModel(kind: .tts, defaults: defaults)
        let translationViewModel = CapabilityModelViewModel(kind: .translation, defaults: defaults)

        ttsViewModel.selectModel(id: CapabilityModelID.cosyVoice3)
        translationViewModel.selectModel(id: CapabilityModelID.systemDefaultTranslation)

        XCTAssertEqual(
            CapabilityModelViewModel(kind: .tts, defaults: defaults).selectedModelID,
            CapabilityModelID.cosyVoice3
        )
        XCTAssertEqual(
            CapabilityModelViewModel(kind: .translation, defaults: defaults).selectedModelID,
            CapabilityModelID.systemDefaultTranslation
        )
    }

    func testSelectingModelMovesItToTop() {
        let suiteName = "test.CapabilityModelViewModel.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let viewModel = CapabilityModelViewModel(kind: .tts, defaults: defaults)

        viewModel.selectModel(id: CapabilityModelID.cosyVoice3)

        XCTAssertEqual(viewModel.selectedModelID, CapabilityModelID.cosyVoice3)
        XCTAssertEqual(viewModel.models.first?.id, CapabilityModelID.cosyVoice3)
    }

    func testStoredSelectedModelLoadsAtTop() {
        let suiteName = "test.CapabilityModelViewModel.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        CapabilityModelViewModel.setSelectedModelID(CapabilityModelID.madladTranslation, kind: .translation, defaults: defaults)

        let viewModel = CapabilityModelViewModel(kind: .translation, defaults: defaults)

        XCTAssertEqual(viewModel.selectedModelID, CapabilityModelID.madladTranslation)
        XCTAssertEqual(viewModel.models.first?.id, CapabilityModelID.madladTranslation)
    }

    func testSoniqoDownloaderDetectsInstalledModelsFromCache() throws {
        let cacheRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("CapabilityModelViewModelTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: cacheRoot) }
        let downloader = SoniqoCapabilityModelDownloader(cacheBaseDirectory: cacheRoot)

        XCTAssertFalse(downloader.isInstalled(modelID: CapabilityModelID.kokoroTTS))

        try makeCachedFile("aufklarer/Kokoro-82M-CoreML", "kokoro_5s.mlmodelc/Manifest.json", cacheRoot: cacheRoot)
        try makeCachedFile(
            "aufklarer/Qwen3-TTS-12Hz-0.6B-Base-MLX-4bit",
            "model.safetensors",
            cacheRoot: cacheRoot
        )
        try makeCachedFile("aufklarer/CosyVoice3-0.5B-MLX-4bit", "llm.safetensors", cacheRoot: cacheRoot)
        try makeCachedFile("aufklarer/MADLAD400-3B-MT-MLX", "int4/model.safetensors", cacheRoot: cacheRoot)

        XCTAssertTrue(downloader.isInstalled(modelID: CapabilityModelID.kokoroTTS))
        XCTAssertTrue(downloader.isInstalled(modelID: CapabilityModelID.qwen3TTS06B4Bit))
        XCTAssertTrue(downloader.isInstalled(modelID: CapabilityModelID.cosyVoice3))
        XCTAssertTrue(downloader.isInstalled(modelID: CapabilityModelID.madladTranslation))
    }

    func testDownloadCoordinatorDeduplicatesConcurrentRequestsForSameModel() async throws {
        let coordinator = CapabilityModelDownloadCoordinator()
        let probe = DownloadCoordinatorProbe()

        let first = Task {
            try await coordinator.run(modelID: CapabilityModelID.kokoroTTS) {
                await probe.recordAndWait()
            }
        }
        while await !probe.isWaiting {
            try await Task.sleep(nanoseconds: 1_000_000)
        }

        let second = Task {
            try await coordinator.run(modelID: CapabilityModelID.kokoroTTS) {
                await probe.recordOnly()
            }
        }
        while await coordinator.waiterCount(modelID: CapabilityModelID.kokoroTTS) == 0 {
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        await probe.finish()

        try await first.value
        try await second.value
        let operationCount = await probe.recordedOperationCount()
        XCTAssertEqual(operationCount, 1)
    }

    private func makeCachedFile(_ modelID: String, _ relativePath: String, cacheRoot: URL) throws {
        let components = modelID.split(separator: "/", maxSplits: 1).map(String.init)
        let modelRoot = cacheRoot
            .appendingPathComponent("models", isDirectory: true)
            .appendingPathComponent(components[0], isDirectory: true)
            .appendingPathComponent(components[1], isDirectory: true)
        let fileURL = modelRoot.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("x".utf8).write(to: fileURL)
    }

}

private actor DownloadCoordinatorProbe {
    private(set) var operationCount = 0
    private var finishContinuation: CheckedContinuation<Void, Never>?

    var isWaiting: Bool {
        finishContinuation != nil
    }

    func recordAndWait() async {
        operationCount += 1
        await withCheckedContinuation { continuation in
            finishContinuation = continuation
        }
    }

    func recordOnly() {
        operationCount += 1
    }

    func finish() {
        finishContinuation?.resume()
        finishContinuation = nil
    }

    func recordedOperationCount() -> Int {
        operationCount
    }
}

private final class CapturingCapabilityModelDownloader: CapabilityModelDownloading, @unchecked Sendable {
    private(set) var downloadedIDs: [String] = []

    func isInstalled(modelID: String) -> Bool {
        downloadedIDs.contains(modelID)
    }

    func download(modelID: String, progress: @escaping @Sendable (Double, String) -> Void) async throws {
        downloadedIDs.append(modelID)
        progress(0.35, "Downloading")
        progress(1.0, "Model loaded")
    }
}

private final class SuspendingCapabilityModelDownloader: CapabilityModelDownloading, @unchecked Sendable {
    private let lock = NSLock()
    private var ids: [String] = []
    private var startContinuation: CheckedContinuation<Void, Never>?
    private var finishContinuation: CheckedContinuation<Void, Never>?

    func isInstalled(modelID: String) -> Bool {
        lock.withLock { ids.contains(modelID) }
    }

    func download(modelID: String, progress: @escaping @Sendable (Double, String) -> Void) async throws {
        lock.withLock {
            ids.append(modelID)
            startContinuation?.resume()
            startContinuation = nil
        }
        await withCheckedContinuation { continuation in
            lock.withLock {
                finishContinuation = continuation
            }
        }
        progress(1.0, "Model loaded")
    }

    func waitUntilStarted() async {
        await withCheckedContinuation { continuation in
            lock.withLock {
                if !ids.isEmpty {
                    continuation.resume()
                } else {
                    startContinuation = continuation
                }
            }
        }
    }

    func finish() {
        lock.withLock {
            finishContinuation?.resume()
            finishContinuation = nil
        }
    }

    func downloadedIDs() -> [String] {
        lock.withLock { ids }
    }
}
